# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class LedgerInstallCommandTest < Minitest::Test
  def test_dry_run_reports_exact_process_without_building_signaling_or_opening
    with_fixture(process_mode: "table") do |fixture|
      stdout, stderr, status = fixture.run("--dry-run", "--no-open")

      assert status.success?, stderr
      assert_includes stdout, "Would build Ledger"
      assert_includes stdout, "Would terminate installed Ledger process(es): 101"
      refute_includes stdout, "102"
      assert_includes stdout, "Would stage and replace /Applications/Ledger.app"
      refute_includes stdout, "Would launch"
      refute_includes fixture.log, "tuist generate"
      refute_includes fixture.log, "xcodebuild"
      refute_includes fixture.log, "installer install"
      refute_includes fixture.log, "open "
    end
  end

  def test_destination_validation_and_build_failures_preserve_status
    [{ validate_destination: 41 }, { generate: 42 }, { build: 43 }].each do |statuses|
      with_fixture(statuses: statuses) do |fixture|
        _stdout, _stderr, status = fixture.run("--no-open")

        assert_equal statuses.values.fetch(0), status.exitstatus
        refute_includes fixture.log, "installer install"
      end
    end
  end

  def test_install_and_open_failures_preserve_status
    with_fixture(statuses: { install: 44 }) do |fixture|
      _stdout, _stderr, status = fixture.run("--no-open")
      assert_equal 44, status.exitstatus
      assert_includes fixture.log, "installer install"
      refute_includes fixture.log, "open "
    end

    with_fixture(statuses: { open: 45 }) do |fixture|
      _stdout, _stderr, status = fixture.run
      assert_equal 45, status.exitstatus
      assert_includes fixture.log, "installer install"
      assert_includes fixture.log, "open /Applications/Ledger.app"
    end
  end

  def test_graceful_and_forced_termination_precede_install
    with_fixture do |fixture|
      fixture.with_process(ignore_term: false) do
        stdout, stderr, status = fixture.run("--no-open")
        assert status.success?, "status=#{status.inspect}\nstdout=#{stdout}\nstderr=#{stderr}\nlog=#{fixture.log}"
        assert_includes stdout, "Terminating installed Ledger"
        refute_includes stderr, "forcing"
        assert_includes fixture.log, "installer install"
      end
    end

    with_fixture do |fixture|
      fixture.with_process(ignore_term: true) do
        _stdout, stderr, status = fixture.run("--no-open")
        assert status.success?, "status=#{status.inspect}\nstderr=#{stderr}\nlog=#{fixture.log}"
        assert_includes stderr, "forcing the exact installed process"
        assert_includes fixture.log, "installer install"
      end
    end
  end

  def test_surviving_process_refuses_replacement
    with_fixture(process_mode: "survives") do |fixture|
      _stdout, stderr, status = fixture.run("--no-open")

      assert_equal 1, status.exitstatus
      assert_includes stderr, "still running; refusing to replace"
      refute_includes fixture.log, "installer install"
    end
  end

  private

  def with_fixture(statuses: {}, process_mode: "none")
    Dir.mktmpdir do |directory|
      yield Fixture.new(Pathname(directory), statuses: statuses, process_mode: process_mode)
    end
  end

  class Fixture
    def initialize(root, statuses:, process_mode:)
      @root = root
      @repository = File.expand_path("../..", __dir__)
      @binary = root / "bin"
      @log = root / "commands.log"
      @marker = root / "process-alive"
      FileUtils.mkdir_p(@binary)
      write_fake_mise(@binary / "mise")
      write_fake_ps(@binary / "ps")
      write_fake_sleep(@binary / "sleep")
      write_fake_open(@binary / "open")
      @environment = {
        "PATH" => "#{@binary}:#{ENV.fetch('PATH')}",
        "FAKE_COMMAND_LOG" => @log.to_s,
        "FAKE_PROCESS_MODE" => process_mode,
        "FAKE_PROCESS_MARKER" => @marker.to_s,
        "FAKE_PROCESS_PID" => "",
        "FAKE_VALIDATE_DESTINATION_STATUS" => statuses.fetch(:validate_destination, 0).to_s,
        "FAKE_GENERATE_STATUS" => statuses.fetch(:generate, 0).to_s,
        "FAKE_BUILD_STATUS" => statuses.fetch(:build, 0).to_s,
        "FAKE_INSTALL_STATUS" => statuses.fetch(:install, 0).to_s,
        "FAKE_OPEN_STATUS" => statuses.fetch(:open, 0).to_s,
      }
    end

    def run(*arguments)
      Open3.capture3(
        @environment,
        File.join(@repository, "Ledger/install"),
        *arguments,
        chdir: @root.to_s,
      )
    end

    def log
      @log.exist? ? @log.read : ""
    end

    def with_process(ignore_term:)
      ready = @root / "process-ready"
      command = ignore_term ? "trap '' TERM; : >\"$1\"; exec /bin/sleep 30" : ": >\"$1\"; exec /bin/sleep 30"
      pid = Process.spawn("/bin/sh", "-c", command, "ledger-test-process", ready.to_s)
      1_000.times do
        break if ready.exist?

        sleep 0.001
      end
      raise "fixture process did not become ready" unless ready.exist?

      @marker.write("alive")
      @environment["FAKE_PROCESS_MODE"] = "pid"
      @environment["FAKE_PROCESS_PID"] = pid.to_s
      reaper = Thread.new do
        Process.wait(pid)
        @marker.delete if @marker.exist?
      rescue Errno::ECHILD
        nil
      end
      yield
    ensure
      begin
        Process.kill("KILL", pid) if pid
      rescue Errno::ESRCH
        nil
      end
      reaper&.join(2)
      @marker.delete if @marker.exist?
      ready&.delete if ready&.exist?
    end

    private

    def write_fake_mise(path)
      path.write(<<~SH)
        #!/bin/sh
        [ "$1" = exec ] && [ "$2" = -- ] || exit 90
        shift 2
        if [ "$1" = ruby ] && [ "$2" = Tools/app_installer.rb ]; then
          shift 2
          command="$1"
          echo "installer $*" >>"$FAKE_COMMAND_LOG"
          case "$command" in
            validate-destination) exit "$FAKE_VALIDATE_DESTINATION_STATUS" ;;
            validate-app) exit 0 ;;
            pids) exec #{RbConfig.ruby} Tools/app_installer.rb "$@" ;;
            install) exit "$FAKE_INSTALL_STATUS" ;;
          esac
          exit 91
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
                mkdir -p "$argument/Build/Products/Release/Ledger.app"
                break
              fi
              previous="$argument"
            done
          fi
          exit "$status"
        fi
        exit 92
      SH
      path.chmod(0o755)
    end

    def write_fake_ps(path)
      path.write(<<~'SH')
        #!/bin/sh
        echo 'ps' >>"$FAKE_COMMAND_LOG"
        executable='/Applications/Ledger.app/Contents/MacOS/Ledger'
        case "$FAKE_PROCESS_MODE" in
          table)
            printf ' 101 %s\n' "$executable"
            printf ' 102 %s\n' '/tmp/Ledger.app/Contents/MacOS/Ledger'
            ;;
          pid)
            [ -e "$FAKE_PROCESS_MARKER" ] && printf ' %s %s\n' "$FAKE_PROCESS_PID" "$executable"
            ;;
          survives)
            printf ' 999999 %s\n' "$executable"
            ;;
        esac
        exit 0
      SH
      path.chmod(0o755)
    end

    def write_fake_sleep(path)
      path.write(<<~'SH')
        #!/bin/sh
        exit 0
      SH
      path.chmod(0o755)
    end

    def write_fake_open(path)
      path.write(<<~'SH')
        #!/bin/sh
        echo "open $*" >>"$FAKE_COMMAND_LOG"
        exit "$FAKE_OPEN_STATUS"
      SH
      path.chmod(0o755)
    end
  end
end
