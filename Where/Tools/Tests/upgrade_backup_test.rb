# frozen_string_literal: true

require "minitest/autorun"
require_relative "../upgrade-backup"

class UpgradeBackupTest < Minitest::Test
  def test_v1_adds_current_tables_without_inventing_recording_consent
    upgraded = upgrade_manifest(base_manifest(1))

    assert_equal 3, upgraded.fetch("formatVersion")
    assert_equal [], upgraded.fetch("recordingDeviceProfiles")
    assert_equal [], upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal [], upgraded.fetch("recordingDeviceRemovals")
    assert_nil upgraded.fetch("samples").first.fetch("recordingDeviceID")
  end

  def test_v1_synthesizes_primary_regions_and_rekeys_legacy_ids
    manifest = base_manifest(1).merge("trackedRegions" => ["california", "newYork"])

    upgraded = upgrade_manifest(manifest)

    assert_equal ["us-CA", "us-NY"], upgraded.fetch("trackedRegions")
    assert_equal [
      { "region" => "us-CA", "appearance" => nil, "order" => 0 },
      { "region" => "us-NY", "appearance" => nil, "order" => 1 },
    ], upgraded.fetch("primaryRegions")
  end

  def test_v2_preserves_primary_region_appearance
    appearance = { "color" => "orange", "emoji" => "🌴", "symbolName" => nil }
    manifest = base_manifest(2).merge(
      "primaryRegions" => [
        { "region" => "us-CA", "appearance" => appearance, "order" => 0 },
      ],
    )

    assert_equal manifest["primaryRegions"], upgrade_manifest(manifest)["primaryRegions"]
  end

  def test_v3_is_idempotent
    once = upgrade_manifest(base_manifest(3))
    assert_equal once, upgrade_manifest(Marshal.load(Marshal.dump(once)))
  end

  def test_normalizes_legacy_iso8601_dates_to_current_unix_timestamps
    manifest = base_manifest(1)
    manifest["exportedAt"] = "2023-11-14T22:13:20Z"
    manifest["samples"].first["timestamp"] = "2023-11-14T22:15:00.500Z"

    upgraded = upgrade_manifest(manifest)

    assert_equal 1_700_000_000.0, upgraded.fetch("exportedAt")
    assert_equal 1_700_000_100.5, upgraded.fetch("samples").first.fetch("timestamp")
  end

  def test_rejects_branch_only_or_future_formats
    error = assert_raises(SystemExit) { upgrade_manifest(base_manifest(4)) }
    assert_equal 1, error.status
  end

  private

  def base_manifest(version)
    {
      "formatVersion" => version,
      "exportedAt" => 0.0,
      "samples" => [{ "id" => "sample" }],
      "evidence" => [],
      "manualDays" => [],
      "dismissedIssues" => [],
      "trackedRegions" => [],
      "assets" => [],
    }
  end
end
