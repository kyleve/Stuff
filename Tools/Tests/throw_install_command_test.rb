# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"

require File.expand_path("ios_device_install_fixture", __dir__)

class ThrowInstallCommandTest < Minitest::Test
  def test_dry_run_reports_throw_without_mutating
    with_fixture do |fixture|
      fixture.write_devices(
        fixture.device(identifier: "tablet-id", udid: "tablet-udid", name: "Kai's iPad"),
      )

      stdout, stderr, status = fixture.run(
        "--device",
        "Kai's iPad",
        "--dry-run",
        "--yes",
      )

      assert status.success?, stderr
      assert_includes stdout, "Would run tuist generate"
      assert_includes stdout, "Would build Throw"
      assert_includes stdout, "Throw.app"
      assert_includes stdout, "Would launch com.stuff.throw"
      assert_includes stderr, "using: Kai's iPad (tablet-id)"
      assert_includes fixture.log, "devicectl list devices"
      refute_includes fixture.log, "tuist"
      refute_includes fixture.log, "xcodebuild"
      refute_includes fixture.log, "device install"
      refute_path_exists fixture.derived_data
    end
  end

  def test_build_installs_and_launches_the_throw_product
    with_fixture do |fixture|
      fixture.write_devices(
        fixture.device(identifier: "tablet-id", udid: "tablet-udid", name: "Kai's iPad"),
      )

      _stdout, stderr, status = fixture.run("--device", "Kai's iPad", "--yes")

      assert status.success?, stderr
      assert_includes fixture.log, "tuist generate --no-open"
      assert_includes fixture.log, "xcodebuild build -workspace Stuff.xcworkspace -scheme Throw"
      assert_includes fixture.log, "device install app --device tablet-id #{built_app(fixture)}"
      assert_includes fixture.log,
        "device process launch --device tablet-id --terminate-existing com.stuff.throw"
    end
  end

  def test_rejects_the_where_only_cloudkit_option_before_running_dependencies
    with_fixture do |fixture|
      _stdout, stderr, status = fixture.run("--cloudkit")

      refute status.success?
      assert_includes stderr, "unknown option '--cloudkit'"
      assert_empty fixture.log
    end
  end

  private

  def built_app(fixture)
    fixture.derived_data / "DerivedData/Build/Products/Debug-iphoneos/Throw.app"
  end

  def with_fixture(team_status: 0, team_id: "TEAM12345", statuses: {})
    Dir.mktmpdir do |directory|
      yield IOSDeviceInstallFixture.new(
        Pathname(directory),
        command: "Throw/install",
        app_name: "Throw",
        derived_data_prefix: "throw-install",
        team_status: team_status,
        team_id: team_id,
        statuses: statuses,
      )
    end
  end
end
