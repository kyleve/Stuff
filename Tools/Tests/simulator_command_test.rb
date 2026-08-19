# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "timeout"
require "tmpdir"

require File.expand_path("../simulator_registry", __dir__)

class SimulatorCommandTest < Minitest::Test
  RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"

  def test_delete_targets_only_the_exact_registered_runtime_device
    with_fixture do |fixture|
      fixture.registry.record(
        name: fixture.owned_name,
        checkout: fixture.repository,
        udid: "owned",
        device: "iPhone 17",
        os: "27.0",
      )
      fixture.write_inventory(
        all: {
          RUNTIME => [fixture.device("owned", fixture.owned_name)],
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0" => [
            fixture.device("other-runtime", fixture.owned_name),
          ],
        },
      )

      _stdout, stderr, status = fixture.run("--delete")

      assert status.success?, stderr
      assert_includes fixture.log, "simctl delete owned"
      refute_includes fixture.log, "other-runtime"
      refute_path_exists fixture.registry_path
    end
  end

  def test_delete_refuses_a_matching_but_unowned_device
    with_fixture do |fixture|
      fixture.write_inventory(
        all: { RUNTIME => [fixture.device("unowned", fixture.owned_name)] },
      )

      _stdout, stderr, status = fixture.run("--delete")

      refute status.success?
      assert_includes stderr, "refusing to delete unowned"
      refute_includes fixture.log, "simctl delete"
    end
  end

  def test_old_ownerless_lock_is_recovered_without_waiting_for_timeout
    with_fixture do |fixture|
      fixture.write_inventory(
        all: { RUNTIME => [fixture.device("claimed", fixture.owned_name)] },
        available: { RUNTIME => [fixture.device("claimed", fixture.owned_name)] },
      )
      FileUtils.mkdir_p(fixture.lock_directory)
      old = Time.now - 10
      File.utime(old, old, fixture.lock_directory)

      stdout, stderr, status = fixture.run("--no-boot")

      assert status.success?, stderr
      assert_equal "claimed\n", stdout
      assert_includes stderr, "clearing stale simulator lock"
      refute_path_exists fixture.lock_directory
      assert_equal "claimed", fixture.registry.load_entry(fixture.owned_name).udid
    end
  end

  def test_interrupted_creation_never_records_an_owner
    with_fixture(create_status: 23) do |fixture|
      fixture.write_inventory(all: {}, available: {})

      _stdout, _stderr, status = fixture.run("--no-boot")

      refute status.success?
      refute_path_exists fixture.registry_path
      refute_path_exists fixture.lock_directory
    end
  end

  def test_active_lock_is_never_stolen
    with_fixture do |fixture|
      FileUtils.mkdir_p(fixture.lock_directory)
      owner = fixture.lock_directory / "owner"
      owner.write("pid=#{Process.pid}\ntoken=active\n")

      _stdout, stderr, status = fixture.run("--no-boot")

      refute status.success?
      assert_includes stderr, "timed out waiting"
      assert_equal "pid=#{Process.pid}\ntoken=active\n", owner.read
      refute_includes fixture.log, "simctl list"
    end
  end

  def test_prune_dry_run_and_delete_use_the_exact_registered_target
    with_fixture do |fixture|
      missing_checkout = fixture.missing_checkout
      fixture.registry.record(
        name: fixture.owned_name,
        checkout: missing_checkout,
        udid: "owned",
        device: "iPhone 17",
        os: "27.0",
      )
      fixture.write_inventory(
        all: {
          RUNTIME => [fixture.device("owned", fixture.owned_name)],
          "another-runtime" => [fixture.device("other", fixture.owned_name)],
        },
      )

      _stdout, stderr, status = fixture.run("--prune", "--dry-run")
      assert status.success?, stderr
      assert_includes stderr, "Would delete"
      refute_includes fixture.log, "simctl delete"
      assert_path_exists fixture.registry_path

      _stdout, stderr, status = fixture.run("--prune")
      assert status.success?, stderr
      assert_includes fixture.log, "simctl delete owned"
      refute_includes fixture.log, "simctl delete other"
      refute_path_exists fixture.registry_path
    end
  end

  def test_malformed_inventory_and_an_uninstalled_runtime_fail_without_mutation
    with_fixture do |fixture|
      fixture.write_raw_inventory("{")

      _stdout, stderr, status = fixture.run("--no-boot")

      refute status.success?
      assert_includes stderr, "unexpected token"
      refute_includes fixture.log, "simctl create"
      refute_includes fixture.log, "simctl delete"
      refute_path_exists fixture.registry_path
    end

    with_fixture(runtime_available: false) do |fixture|
      fixture.write_inventory(all: {}, available: {})

      _stdout, stderr, status = fixture.run("--no-boot")

      refute status.success?
      assert_includes stderr, "isn't installed or isn't usable"
      refute_includes fixture.log, "simctl create"
      refute_path_exists fixture.registry_path
    end
  end

  def test_failed_registry_record_and_device_delete_remain_observable
    with_fixture(record_status: 44) do |fixture|
      fixture.write_inventory(all: {}, available: {})

      _stdout, _stderr, status = fixture.run("--no-boot")

      assert_equal 44, status.exitstatus
      assert_includes fixture.log, "simctl create"
      refute_path_exists fixture.registry_path
    end

    with_fixture(delete_status: 53) do |fixture|
      fixture.registry.record(
        name: fixture.owned_name,
        checkout: fixture.repository,
        udid: "owned",
        device: "iPhone 17",
        os: "27.0",
      )
      fixture.write_inventory(all: { RUNTIME => [fixture.device("owned", fixture.owned_name)] })

      _stdout, _stderr, status = fixture.run("--delete")

      assert_equal 53, status.exitstatus
      assert_includes fixture.log, "simctl delete owned"
      assert_equal "owned", fixture.registry.load_entry(fixture.owned_name).udid
    end
  end

  def test_recreate_deletes_the_exact_claim_then_records_the_new_device
    with_fixture(dynamic_inventory: true) do |fixture|
      fixture.registry.record(
        name: fixture.owned_name,
        checkout: fixture.repository,
        udid: "old",
        device: "iPhone 17",
        os: "27.0",
      )
      fixture.write_inventory(all: { RUNTIME => [fixture.device("old", fixture.owned_name)] })

      stdout, stderr, status = fixture.run("--recreate", "--no-boot")

      assert status.success?, stderr
      assert_equal "created\n", stdout
      assert_includes fixture.log, "simctl delete old"
      assert_equal 1, fixture.log.scan("simctl create").length
      assert_equal "created", fixture.registry.load_entry(fixture.owned_name).udid
    end
  end

  def test_concurrent_first_resolution_creates_and_records_exactly_one_device
    with_fixture(dynamic_inventory: true, create_delay: 0.2) do |fixture|
      fixture.write_inventory(all: {}, available: {})

      results = 4.times.map do
        Thread.new { fixture.run("--no-boot") }
      end.map(&:value)

      results.each do |stdout, stderr, status|
        assert status.success?, stderr
        assert_equal "created\n", stdout
      end
      assert_equal 1, fixture.log.scan("simctl create").length
      assert_equal "created", fixture.registry.load_entry(fixture.owned_name).udid
      refute_path_exists fixture.lock_directory
    end
  end

  private

  def with_fixture(
    create_status: 0,
    delete_status: 0,
    record_status: 0,
    runtime_available: true,
    dynamic_inventory: false,
    create_delay: 0
  )
    Dir.mktmpdir do |directory|
      yield Fixture.new(
        Pathname(directory),
        create_status: create_status,
        delete_status: delete_status,
        record_status: record_status,
        runtime_available: runtime_available,
        dynamic_inventory: dynamic_inventory,
        create_delay: create_delay,
      )
    end
  end

  class Fixture
    attr_reader :owned_name, :repository, :registry, :registry_path, :lock_directory

    def initialize(
      root,
      create_status:,
      delete_status:,
      record_status:,
      runtime_available:,
      dynamic_inventory:,
      create_delay:
    )
      @root = root
      @repository = File.expand_path("../..", __dir__)
      checkout_hash = Digest::SHA256.hexdigest(repository)[0, 8]
      @owned_name = "Stuff-#{File.basename(repository)}-#{checkout_hash}-iPhone-17-27.0"
      home = root / "home"
      temporary = root / "tmp"
      binary = root / "bin"
      FileUtils.mkdir_p([home, temporary, binary])
      @registry_directory = home / "Library/Application Support/Stuff/simulators"
      @registry = SimulatorRegistry.new(directory: @registry_directory.to_s)
      @registry_path = @registry_directory / owned_name
      @lock_directory = temporary / "stuff-simulator-#{checkout_hash}.lock"
      @all_path = root / "all.json"
      @available_path = root / "available.json"
      @log_path = root / "xcrun.log"
      write_fake_mise(binary / "mise")
      write_fake_xcrun(
        binary / "xcrun",
        create_status: create_status,
        delete_status: delete_status,
        runtime_available: runtime_available,
      )
      write_fake_sleep(binary / "sleep")
      @environment = {
        "PATH" => "#{binary}:#{ENV.fetch('PATH')}",
        "HOME" => home.to_s,
        "TMPDIR" => temporary.to_s,
        "FAKE_ALL_JSON" => @all_path.to_s,
        "FAKE_AVAILABLE_JSON" => @available_path.to_s,
        "FAKE_XCRUN_LOG" => @log_path.to_s,
        "FAKE_RECORD_STATUS" => record_status.to_s,
        "FAKE_DYNAMIC_INVENTORY" => dynamic_inventory ? "1" : "0",
        "FAKE_CREATE_DELAY" => create_delay.to_s,
      }
      write_inventory(all: {}, available: {})
    end

    def write_inventory(all:, available: all)
      @all_path.write(JSON.generate("devices" => all))
      @available_path.write(JSON.generate("devices" => available))
    end

    def write_raw_inventory(contents)
      @all_path.write(contents)
      @available_path.write(contents)
    end

    def device(udid, name)
      { "udid" => udid, "name" => name, "state" => "Shutdown" }
    end

    def run(*arguments)
      Timeout.timeout(15) do
        Open3.capture3(
          @environment,
          File.join(repository, "simulator"),
          "--device",
          "iPhone 17",
          "--os",
          "27.0",
          *arguments,
          chdir: repository,
        )
      end
    end

    def log
      @log_path.exist? ? @log_path.read : ""
    end

    def missing_checkout
      parent = @root / "checkouts"
      FileUtils.mkdir_p(parent)
      (parent / "gone").to_s
    end

    private

    def write_fake_mise(path)
      path.write(<<~SH)
        #!/bin/sh
        [ "$1" = exec ] && [ "$2" = -- ] || exit 90
        shift 2
        [ "$1" = ruby ] || exit 91
        shift
        if [ "$2" = record ] && [ "${FAKE_RECORD_STATUS:-0}" -ne 0 ]; then
          exit "$FAKE_RECORD_STATUS"
        fi
        exec #{RbConfig.ruby} "$@"
      SH
      path.chmod(0o755)
    end

    def write_fake_xcrun(path, create_status:, delete_status:, runtime_available:)
      path.write(<<~SH)
        #!/bin/sh
        printf '%s\n' "$*" >>"$FAKE_XCRUN_LOG"
        if [ "$1 $2 $3 $4" = "simctl list devices available" ]; then
          cat "$FAKE_AVAILABLE_JSON"
        elif [ "$1 $2 $3" = "simctl list devices" ]; then
          cat "$FAKE_ALL_JSON"
        elif [ "$1 $2 $3" = "simctl list devicetypes" ]; then
          printf '%s\n' '{"devicetypes":[{"name":"iPhone 17","identifier":"type-id"}]}'
        elif [ "$1 $2 $3" = "simctl list runtimes" ]; then
          printf '%s\n' '{"runtimes":[{"identifier":"#{RUNTIME}","isAvailable":#{runtime_available}}]}'
        elif [ "$1 $2" = "simctl create" ]; then
          if [ #{create_status} -eq 0 ]; then
            /bin/sleep "${FAKE_CREATE_DELAY:-0}"
            if [ "${FAKE_DYNAMIC_INVENTORY:-0}" = 1 ]; then
              /usr/bin/python3 - "$FAKE_ALL_JSON" "$FAKE_AVAILABLE_JSON" "$3" <<'PY'
        import json
        import sys
        payload = {"devices": {"#{RUNTIME}": [{"udid": "created", "name": sys.argv[3], "state": "Shutdown"}]}}
        for inventory_path in sys.argv[1:3]:
            with open(inventory_path, "w") as stream:
                json.dump(payload, stream)
        PY
            fi
            printf '%s\n' created
          fi
          exit #{create_status}
        elif [ "$1 $2" = "simctl delete" ]; then
          if [ #{delete_status} -eq 0 ] && [ "${FAKE_DYNAMIC_INVENTORY:-0}" = 1 ]; then
            printf '%s\n' '{"devices":{}}' >"$FAKE_ALL_JSON"
            printf '%s\n' '{"devices":{}}' >"$FAKE_AVAILABLE_JSON"
          fi
          exit #{delete_status}
        elif [ "$1 $2" = "simctl bootstatus" ]; then
          exit 0
        else
          exit 92
        fi
      SH
      path.chmod(0o755)
    end

    def write_fake_sleep(path)
      path.write("#!/bin/sh\nexit 0\n")
      path.chmod(0o755)
    end
  end
end
