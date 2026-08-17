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

  private

  def with_fixture(team_status: 0)
    Dir.mktmpdir do |directory|
      yield Fixture.new(Pathname(directory), team_status: team_status)
    end
  end

  class Fixture
    attr_reader :derived_data

    def initialize(root, team_status:)
      @root = root
      @repository = File.expand_path("../..", __dir__)
      @home = root / "home"
      @temporary = root / "tmp"
      binary = root / "bin"
      FileUtils.mkdir_p([@home, @temporary, binary])
      @devices = root / "devices.json"
      @log = root / "commands.log"
      @derived_data = @home / "Library/Developer/Xcode/DerivedData/where-install-#{File.basename(@repository)}"
      write_fake_mise(binary / "mise", team_status)
      write_fake_xcrun(binary / "xcrun")
      @environment = {
        "PATH" => "#{binary}:#{ENV.fetch('PATH')}",
        "HOME" => @home.to_s,
        "TMPDIR" => @temporary.to_s,
        "FAKE_DEVICES" => @devices.to_s,
        "FAKE_COMMAND_LOG" => @log.to_s,
      }
      write_devices
    end

    def write_devices(*devices)
      @devices.write(JSON.generate("result" => { "devices" => devices }))
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

    def log
      @log.exist? ? @log.read : ""
    end

    private

    def write_fake_mise(path, team_status)
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
          printf '%s' TEAM12345
          exit 0
        fi
        if [ "$1" = ruby ]; then
          shift
          exec #{RbConfig.ruby} "$@"
        fi
        echo "$*" >>"$FAKE_COMMAND_LOG"
        exit 91
      SH
      path.chmod(0o755)
    end

    def write_fake_xcrun(path)
      path.write(<<~'SH')
        #!/bin/sh
        echo "$*" >>"$FAKE_COMMAND_LOG"
        if [ "$1 $2 $3" != "devicectl list devices" ]; then
          exit 92
        fi
        shift 3
        while [ $# -gt 0 ]; do
          if [ "$1" = --json-output ]; then
            cp "$FAKE_DEVICES" "$2"
            exit 0
          fi
          shift
        done
        exit 93
      SH
      path.chmod(0o755)
    end
  end
end
