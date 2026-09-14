# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class ProfileCommandTest < Minitest::Test
  def test_export_failure_stops_before_project_generation_or_build
    with_fixture(export_status: 47) do |fixture|
      _stdout, _stderr, status = fixture.run

      assert_equal 47, status.exitstatus
      assert_includes fixture.log, "python3 Tools/porthole_export.py"
      refute_includes fixture.log, "tuist generate"
      refute_includes fixture.log, "xcodebuild"
    end
  end

  def test_exports_bindings_before_generation_and_preserves_generation_failure
    with_fixture(export_status: 0) do |fixture|
      _stdout, _stderr, status = fixture.run

      assert_equal 48, status.exitstatus
      assert_operator fixture.log.index("python3 Tools/porthole_export.py"), :<, fixture.log.index("tuist generate")
      refute_includes fixture.log, "xcodebuild"
    end
  end

  private

  def with_fixture(export_status:)
    Dir.mktmpdir do |directory|
      yield Fixture.new(Pathname(directory), export_status: export_status)
    end
  end

  class Fixture
    def initialize(root, export_status:)
      @root = root
      @log = root / "commands.log"
      binary = root / "bin"
      FileUtils.mkdir_p(binary)
      FileUtils.cp(File.expand_path("../../profile", __dir__), root / "profile")
      (root / "simulator").write(<<~'SH')
        #!/bin/sh
        echo 'simulator' >>"$FAKE_COMMAND_LOG"
        echo '00000000-0000-0000-0000-000000000001'
      SH
      (root / "simulator").chmod(0o755)
      (binary / "mise").write(<<~'SH')
        #!/bin/sh
        [ "$1" = exec ] && [ "$2" = -- ] || exit 90
        shift 2
        echo "$*" >>"$FAKE_COMMAND_LOG"
        if [ "$1" = python3 ] && [ "$2" = Tools/porthole_export.py ]; then
          exit "$FAKE_EXPORT_STATUS"
        fi
        [ "$1" = tuist ] && exit 48
        exit 91
      SH
      (binary / "mise").chmod(0o755)
      @environment = {
        "PATH" => "#{binary}:#{ENV.fetch('PATH')}",
        "PROFILE_WORKDIR" => (root / "artifacts").to_s,
        "FAKE_COMMAND_LOG" => @log.to_s,
        "FAKE_EXPORT_STATUS" => export_status.to_s,
      }
    end

    def run
      Open3.capture3(@environment, (@root / "profile").to_s, "--build-only", "--no-snapshots")
    end

    def log
      @log.exist? ? @log.read : ""
    end
  end
end
