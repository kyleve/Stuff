# frozen_string_literal: true

require "minitest/autorun"
require_relative "../upgrade-backup"

class UpgradeBackupTest < Minitest::Test
  def test_v1_adds_current_tables_without_inventing_recording_consent
    upgraded = upgrade_manifest(base_manifest(1))

    assert_equal 6, upgraded.fetch("formatVersion")
    assert_equal [], upgraded.fetch("recordingDeviceProfiles")
    assert_equal [], upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal [], upgraded.fetch("recordingDeviceRemovals")
    assert_equal [], upgraded.fetch("plannedStayRecords")
    assert_equal [], upgraded.fetch("homeRegionRecords")
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

  def test_v5_stay_revisions_share_one_identity_and_keep_tombstones
    timestamp = Time.iso8601("2026-09-13T23:45:00Z").to_f
    revisions = [
      { "id" => "old", "updatedAt" => timestamp, "value" => {
        "region" => "us-NY", "through" => { "year" => 2026, "month" => 10, "day" => 1 },
      } },
      { "id" => "clear", "updatedAt" => timestamp + 1 },
    ]
    manifest = base_manifest(5).merge("plannedStayRecords" => revisions)

    upgraded = upgrade_manifest(manifest).fetch("plannedStayRecords")

    assert_equal %w[old clear], upgraded.map { |record| record.fetch("id") }
    assert_equal [LEGACY_PLANNED_STAY_ID], upgraded.map { |record| record.fetch("stayID") }.uniq
    assert_equal timestamp, upgraded.first.fetch("updatedAt")
    assert_nil upgraded.last["value"]
    value = upgraded.first.fetch("value")
    assert_equal LEGACY_PLANNED_STAY_ID, value.fetch("id")
    assert_equal "us-NY", value.fetch("region")
    assert_equal({ "year" => 2026, "month" => 9, "day" => 13 }, value.fetch("arrival").fetch("earliest"))
    assert_equal value.fetch("arrival").fetch("earliest"), value.fetch("arrival").fetch("latest")
    assert_equal({ "year" => 2026, "month" => 10, "day" => 1 }, value.fetch("departure").fetch("earliest"))
    assert_equal value.fetch("departure").fetch("earliest"), value.fetch("departure").fetch("latest")
  end

  def test_v5_inferred_arrival_is_independent_of_export_date
    manifest = base_manifest(5).merge("plannedStayRecords" => [{
      "id" => "revision", "updatedAt" => "2026-09-13T23:45:00-04:00", "value" => {
        "region" => "us-NY", "through" => { "year" => 2026, "month" => 10, "day" => 1 },
      },
    }])
    another = Marshal.load(Marshal.dump(manifest)).merge("exportedAt" => 2_000_000_000)

    first = upgrade_manifest(manifest).fetch("plannedStayRecords")
    second = upgrade_manifest(another).fetch("plannedStayRecords")

    assert_equal first, second
    assert_equal({ "year" => 2026, "month" => 9, "day" => 14 }, first.first.fetch("value").fetch("arrival").fetch("earliest"))
  end

  def test_v5_inferred_arrival_is_clamped_to_departure_for_clock_skew_or_completed_stays
    manifest = base_manifest(5).merge("plannedStayRecords" => [{
      "id" => "revision", "updatedAt" => Time.iso8601("2026-12-01T00:00:00Z").to_f, "value" => {
        "region" => "us-NY", "through" => { "year" => 2026, "month" => 9, "day" => 1 },
      },
    }])
    upgraded = upgrade_manifest(manifest)
    value = upgraded.fetch("plannedStayRecords").first.fetch("value")

    assert_equal value.fetch("departure"), value.fetch("arrival")
    assert_equal upgraded, upgrade_manifest(Marshal.load(Marshal.dump(upgraded)))
  end

  def test_v5_inferred_arrival_uses_gregorian_leap_dates_before_the_historical_calendar_switch
    leap_day = { "year" => 1504, "month" => 2, "day" => 29 }
    manifest = base_manifest(5).merge("plannedStayRecords" => [{
      "id" => "revision", "updatedAt" => Time.utc(1504, 2, 29).to_f, "value" => {
        "region" => "us-NY", "through" => leap_day,
      },
    }])

    value = upgrade_manifest(manifest).fetch("plannedStayRecords").first.fetch("value")

    assert_equal leap_day, value.fetch("arrival").fetch("earliest")
    assert_equal leap_day, value.fetch("departure").fetch("earliest")
  end

  def test_v5_rejects_a_julian_only_leap_date
    manifest = base_manifest(5).merge("plannedStayRecords" => [{
      "id" => "revision", "updatedAt" => Time.utc(1500, 2, 28).to_f, "value" => {
        "region" => "us-NY", "through" => { "year" => 1500, "month" => 2, "day" => 29 },
      },
    }])

    error = assert_raises(SystemExit) { upgrade_manifest(manifest) }
    assert_equal 1, error.status
  end

  def test_v6_keeps_flexible_windows_and_home_tombstones_unchanged
    manifest = base_manifest(6).merge(
      "plannedStayRecords" => [{ "id" => "revision", "stayID" => "stay", "value" => {
        "id" => "stay", "region" => "us-NY",
        "arrival" => { "earliest" => { "year" => 2026, "month" => 10, "day" => 10 }, "latest" => { "year" => 2026, "month" => 10, "day" => 12 } },
        "departure" => { "earliest" => { "year" => 2026, "month" => 10, "day" => 20 }, "latest" => { "year" => 2026, "month" => 10, "day" => 25 } },
      } }],
      "homeRegionRecords" => [{ "id" => "home", "region" => "us-CA", "updatedAt" => 1 }, { "id" => "clear", "updatedAt" => 2 }],
    )
    stays = Marshal.load(Marshal.dump(manifest.fetch("plannedStayRecords")))
    homes = Marshal.load(Marshal.dump(manifest.fetch("homeRegionRecords")))

    upgraded = upgrade_manifest(manifest)

    assert_equal stays, upgraded.fetch("plannedStayRecords")
    assert_equal homes, upgraded.fetch("homeRegionRecords")
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
