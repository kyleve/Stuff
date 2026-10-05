# frozen_string_literal: true

require "minitest/autorun"
require_relative "../upgrade-backup"
require_relative "../../../.agents/skills/upgrade-where-backup/scripts/upgrade_and_verify"

class UpgradeBackupTest < Minitest::Test
  def test_v1_adds_current_tables_without_inventing_recording_consent
    upgraded = upgrade_manifest(base_manifest(1))

    assert_equal 6, upgraded.fetch("formatVersion")
    assert_equal [], upgraded.fetch("recordingDeviceProfiles")
    assert_equal [], upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal [], upgraded.fetch("recordingDeviceRemovals")
    assert_equal [], upgraded.fetch("plannedStayRecords")
    assert_equal [], upgraded.fetch("sampleAttributionRevisions")
    assert_nil upgraded.fetch("samples").first.fetch("motion")
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

  def test_v3_reshapes_recording_device_data
    manifest = base_manifest(3).merge(
      "recordingDeviceProfiles" => [{
        "kind" => "other",
        "registrationEpochID" => "generation-id",
      }],
      "recordingDeviceMetadataChanges" => [{
        "field" => "nickname",
        "nickname" => "Travel iPad",
      }, {
        "field" => "nickname",
      }],
    )

    upgraded = upgrade_manifest(manifest)

    assert_equal 6, upgraded.fetch("formatVersion")
    assert_equal({
      "kind" => { "other" => {} },
      "registrationGenerationID" => "generation-id",
    }, upgraded.fetch("recordingDeviceProfiles").first)
    assert_equal({
      "payload" => { "field" => "nickname", "nickname" => "Travel iPad" },
    }, upgraded.fetch("recordingDeviceMetadataChanges").first)
    assert_equal({
      "payload" => { "field" => "nickname" },
    }, upgraded.fetch("recordingDeviceMetadataChanges").last)
  end

  def test_v6_is_idempotent
    once = upgrade_manifest(base_manifest(6))
    assert_equal once, upgrade_manifest(Marshal.load(Marshal.dump(once)))
  end

  def test_v5_gains_empty_corrections_and_unknown_motion_without_altering_raw_fixes
    manifest = base_manifest(5)
    manifest["samples"] = [{ "id" => "sample", "timestamp" => 1000.25, "coordinate" => { "latitude" => 40, "longitude" => -100 } }]
    original = Marshal.load(Marshal.dump(manifest["samples"].first))

    upgraded = upgrade_manifest(manifest)

    assert_equal original.merge("recordingDeviceID" => nil, "motion" => nil), upgraded.fetch("samples").first
    assert_equal [], upgraded.fetch("sampleAttributionRevisions")
  end

  def test_v6_preserves_motion_and_every_correction_revision_including_tombstones
    motion = {
      "speed" => { "metersPerSecond" => 240, "accuracyMetersPerSecond" => 2 },
      "altitude" => { "meters" => 11000, "accuracyMeters" => 12 },
    }
    revisions = [nil, [], ["us-NY"]].each_with_index.map do |regions, index|
      { "id" => "revision-#{index}", "sampleID" => "sample", "updatedAt" => 1000 + index, "replacementRegions" => regions }
    end
    manifest = base_manifest(6).merge("sampleAttributionRevisions" => revisions)
    manifest["samples"].first["motion"] = motion

    upgraded = upgrade_manifest(manifest)

    assert_equal motion, upgraded.fetch("samples").first.fetch("motion")
    assert_equal revisions, upgraded.fetch("sampleAttributionRevisions")
    assert_equal upgraded, upgrade_manifest(Marshal.load(Marshal.dump(upgraded)))
  end

  def test_verification_driver_counts_planned_stays_and_correction_tombstones
    manifest = upgrade_manifest(base_manifest(6))
    manifest["plannedStayRecords"] = [{ "id" => "stay", "value" => nil, "updatedAt" => 1000 }]
    manifest["sampleAttributionRevisions"] = [{ "id" => "reset", "sampleID" => "sample", "updatedAt" => 1001 }]
    driver = UpgradeAndVerify.new(["input.zip", "output.zip"])
    counts = driver.send(:expected_counts, manifest)
    configuration = driver.send(:verification_configuration, manifest)

    assert_equal 1, counts.fetch("plannedStayRecords")
    assert_equal 1, counts.fetch("sampleAttributionRevisions")
    assert_equal 1, configuration.fetch(:plannedStayRecordsCount)
    assert_equal 1, configuration.fetch(:sampleAttributionRevisionsCount)
    manifest["sampleAttributionRevisions"] = []
    assert_raises(RuntimeError) { driver.send(:verify_counts!, manifest, counts) }
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
    error = assert_raises(SystemExit) { upgrade_manifest(base_manifest(7)) }
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
