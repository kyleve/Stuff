# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class WhereInstallCommandTest < Minitest::Test
  def test_dry_run_resolves_exact_device_without_building_or_installing
    with_fixture do |fixture|
      fixture.write_devices(
        fixture.device(identifier: "phone-one", udid: "udid-one", name: "Kai's iPhone"),
        fixture.device(identifier: "phone-two", udid: "udid-two", name: "Other Phone"),
      )

      stdout, stderr, status = fixture.run("--device", "Kai's iPhone", "--dry-run", "--yes")

      assert status.success?, stderr
      assert_includes stdout, "Would run tuist generate"
      assert_includes stdout, "Would build Where"
      assert_includes stdout, "Would install"
      assert_includes stdout, "phone-one"
      assert_includes stdout, "Would launch com.stuff.where"
      assert_includes stderr, "using: Kai's iPhone (phone-one)"
      assert_includes fixture.log, "devicectl list devices"
      refute_includes fixture.log, "tuist"
      refute_includes fixture.log, "xcodebuild"
      refute_includes fixture.log, "device install"
      refute_path_exists fixture.derived_data
    end
  end

  def test_dry_run_refuses_ambiguous_devices_before_any_mutation
    with_fixture do |fixture|
      fixture.write_devices(
        fixture.device(identifier: "one", udid: "one", name: "First"),
        fixture.device(identifier: "two", udid: "two", name: "Second"),
      )

      _stdout, stderr, status = fixture.run("--dry-run", "--yes")

      refute status.success?
      assert_includes stderr, "multiple physical iOS devices"
      refute_includes fixture.log, "device install"
      refute_includes fixture.log, "xcodebuild"
    end
  end

  def test_signing_lookup_failure_keeps_mise_status_and_stderr
    with_fixture(team_status: 27) do |fixture|
      _stdout, stderr, status = fixture.run("--dry-run", "--yes")

      assert_equal 27, status.exitstatus
      assert_includes stderr, "mise team lookup failed"
      refute_includes stderr, "no Apple Developer team configured"
      assert_equal "mise team\n", fixture.log
    end
  end

  def test_unset_signing_team_fails_before_any_build_or_device_lookup
    with_fixture(team_id: "") do |fixture|
      _stdout, stderr, status = fixture.run("--dry-run", "--yes")

      assert_equal 1, status.exitstatus
      assert_includes stderr, "no Apple Developer team configured"
      assert_equal "mise team\n", fixture.log
    end
  end

  def test_malformed_and_schema_shifted_device_json_fail_without_mutating
    ["{", JSON.generate("result" => { "devices" => {} })].each do |json|
      with_fixture do |fixture|
        fixture.write_raw_devices(json)

        _stdout, stderr, status = fixture.run("--dry-run", "--yes")

        assert_equal 1, status.exitstatus
        assert_match(/couldn't read devicectl|no devices array/, stderr)
        refute_includes fixture.log, "device install"
        refute_includes fixture.log, "xcodebuild"
      end
    end
  end

  def test_device_names_are_forwarded_without_shell_interpretation
    with_fixture do |fixture|
      name = "Kai's 📱\tLab Phone"
      fixture.write_devices(fixture.device(identifier: "phone-id", udid: "phone-udid", name: name))

      stdout, stderr, status = fixture.run("--device", name, "--dry-run", "--yes")

      assert status.success?, stderr
      assert_includes stdout, name
      assert_includes stderr, name
      refute_includes fixture.log, "device install"
    end
  end

  def test_child_failures_preserve_the_failing_status_and_stop_later_work
    scenarios = [
      [{ list: 31 }, ["--dry-run", "--yes"], 31, "devicectl list devices", "device install"],
      [{ generate: 32 }, ["--yes"], 32, "tuist generate", "xcodebuild"],
      [{ build: 33 }, ["--yes"], 33, "xcodebuild", "devicectl list devices"],
      [{ install: 34 }, ["--yes"], 34, "device install app", "device process launch"],
      [{ launch: 35 }, ["--yes"], 35, "device process launch", nil],
    ]
    scenarios.each do |statuses, arguments, expected_status, expected_command, forbidden_command|
      with_fixture(statuses: statuses) do |fixture|
        fixture.write_devices(fixture.device(identifier: "phone", udid: "udid", name: "Phone"))

        _stdout, _stderr, status = fixture.run(*arguments)

        assert_equal expected_status, status.exitstatus
        assert_includes fixture.log, expected_command
        refute_includes fixture.log, forbidden_command if forbidden_command
      end
    end
  end

  def test_confirmation_eof_cancels_before_install
    with_fixture do |fixture|
      fixture.write_devices(fixture.device(identifier: "phone", udid: "udid", name: "Phone"))

      _stdout, _stderr, status = fixture.run_interactively_with_eof

      refute status.success?
      refute_includes fixture.log, "device install app"
    end
  end

  private

  def with_fixture(team_status: 0, team_id: "TEAM12345", statuses: {})
    Dir.mktmpdir do |directory|
      yield Fixture.new(Pathname(directory), team_status: team_status, team_id: team_id, statuses: statuses)
    end
  end

  class Fixture
    attr_reader :derived_data

    def initialize(root, team_status:, team_id:, statuses:)
      @root = root
      @repository = File.expand_path("../..", __dir__)
      @home = root / "home"
      @temporary = root / "tmp"
      binary = root / "bin"
      FileUtils.mkdir_p([@home, @temporary, binary])
      @devices = root / "devices.json"
      @log = root / "commands.log"
      @derived_data = @home / "Library/Developer/Xcode/DerivedData/where-install-#{File.basename(@repository)}"
      write_fake_mise(binary / "mise", team_status, team_id)
      write_fake_xcrun(binary / "xcrun")
      @environment = {
        "PATH" => "#{binary}:#{ENV.fetch('PATH')}",
        "HOME" => @home.to_s,
        "TMPDIR" => @temporary.to_s,
        "FAKE_DEVICES" => @devices.to_s,
        "FAKE_COMMAND_LOG" => @log.to_s,
        "FAKE_GENERATE_STATUS" => statuses.fetch(:generate, 0).to_s,
        "FAKE_BUILD_STATUS" => statuses.fetch(:build, 0).to_s,
        "FAKE_LIST_STATUS" => statuses.fetch(:list, 0).to_s,
        "FAKE_INSTALL_STATUS" => statuses.fetch(:install, 0).to_s,
        "FAKE_LAUNCH_STATUS" => statuses.fetch(:launch, 0).to_s,
      }
      write_devices
    end

    def write_devices(*devices)
      @devices.write(JSON.generate("result" => { "devices" => devices }))
    end

    def write_raw_devices(json)
      @devices.write(json)
    end

    def device(identifier:, udid:, name:)
      {
        "identifier" => identifier,
        "properties" => {
          "hardware" => { "platform" => "iOS", "reality" => "physical", "udid" => udid },
          "connection" => { "state" => "connected" },
          "state" => { "name" => name },
        },
      }
    end

    def run(*arguments)
      Open3.capture3(
        @environment,
        File.join(@repository, "Where/install"),
        *arguments,
        chdir: @repository,
      )
    end

    def run_interactively_with_eof
      Open3.capture3(
        @environment,
        "/usr/bin/script",
        "-q",
        "/dev/null",
        File.join(@repository, "Where/install"),
        chdir: @repository,
        stdin_data: "",
      )
    end

    def log
      @log.exist? ? @log.read : ""
    end

    private

    def write_fake_mise(path, team_status, team_id)
      path.write(<<~SH)
        #!/bin/sh
        [ "$1" = exec ] && [ "$2" = -- ] || exit 90
        shift 2
        if [ "$1" = sh ]; then
          echo 'mise team' >>"$FAKE_COMMAND_LOG"
          if [ #{team_status} -ne 0 ]; then
            echo 'mise team lookup failed' >&2
            exit #{team_status}
          fi
          printf '%s' #{team_id}
          exit 0
        fi
        if [ "$1" = ruby ]; then
          shift
          exec #{RbConfig.ruby} "$@"
        fi
        echo "$*" >>"$FAKE_COMMAND_LOG"
        if [ "$1" = tuist ]; then
          exit "$FAKE_GENERATE_STATUS"
        fi
        if [ "$1" = xcodebuild ]; then
          status="$FAKE_BUILD_STATUS"
          if [ "$status" -eq 0 ]; then
            previous=""
            for argument in "$@"; do
              if [ "$previous" = -derivedDataPath ]; then
                mkdir -p "$argument/Build/Products/Debug-iphoneos/Where.app"
                break
              fi
              previous="$argument"
            done
          fi
          exit "$status"
        fi
        exit 91
      SH
      path.chmod(0o755)
    end

    def write_fake_xcrun(path)
      path.write(<<~'SH')
        #!/bin/sh
        echo "$*" >>"$FAKE_COMMAND_LOG"
        if [ "$1 $2 $3" = "devicectl list devices" ]; then
          [ "$FAKE_LIST_STATUS" -eq 0 ] || exit "$FAKE_LIST_STATUS"
          shift 3
          while [ $# -gt 0 ]; do
            if [ "$1" = --json-output ]; then
              cp "$FAKE_DEVICES" "$2"
              exit 0
            fi
            shift
          done
          exit 93
        fi
        [ "$1 $2 $3 $4" = "devicectl device install app" ] && exit "$FAKE_INSTALL_STATUS"
        [ "$1 $2 $3 $4" = "devicectl device process launch" ] && exit "$FAKE_LAUNCH_STATUS"
        exit 92
      SH
      path.chmod(0o755)
    end
  end
end
