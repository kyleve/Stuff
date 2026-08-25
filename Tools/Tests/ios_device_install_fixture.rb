# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"

# Runs an iOS app installer against fake build and device commands.
class IOSDeviceInstallFixture
  attr_reader :derived_data

  def initialize(
    root,
    command:,
    app_name:,
    derived_data_prefix:,
    team_status:,
    team_id:,
    statuses:
  )
    @root = root
    @repository = File.expand_path("../..", __dir__)
    @command = File.join(@repository, command)
    @home = root / "home"
    @temporary = root / "tmp"
    binary = root / "bin"
    FileUtils.mkdir_p([@home, @temporary, binary])
    @devices = root / "devices.json"
    @log = root / "commands.log"
    @derived_data = @home / "Library/Developer/Xcode/DerivedData/#{derived_data_prefix}-#{File.basename(@repository)}"
    write_fake_mise(binary / "mise", team_status, team_id, app_name)
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
      "FAKE_STALE_THROW_RESOURCES" => statuses.fetch(:stale_throw_resources, false) ? "1" : "0",
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
      @command,
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
      @command,
      chdir: @repository,
      stdin_data: "",
    )
  end

  def log
    @log.exist? ? @log.read : ""
  end

  private

  def write_fake_mise(path, team_status, team_id, app_name)
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
          derived=""
          configuration="Debug"
          for argument in "$@"; do
            if [ "$previous" = -derivedDataPath ]; then
              derived="$argument"
            elif [ "$previous" = -configuration ]; then
              configuration="$argument"
            fi
            previous="$argument"
          done
          app="$derived/Build/Products/$configuration-iphoneos/#{app_name}.app"
          if [ "$2" = clean ]; then
            rm -rf "$app"
            touch "$derived/.fake-cleaned"
          else
            mkdir -p "$app"
            if [ "#{app_name}" = Throw ]; then
              resources="$app/Stuff_ThrowCore.bundle"
              mkdir -p "$resources"
              touch "$resources/geography-v2.json"
              if [ "$FAKE_STALE_THROW_RESOURCES" != 1 ] || [ -f "$derived/.fake-cleaned" ]; then
                touch "$resources/aircraft-types-v1.json"
              fi
            fi
          fi
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
