# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../upgrade-backup"
require_relative "../../../.agents/skills/upgrade-where-backup/scripts/upgrade_and_verify"

class UpgradeBackupTest < Minitest::Test
  def test_v8_place_scope_upgrades_without_rewriting_immutable_payloads_or_unknown_records
    directory = File.expand_path("../../WhereCore/Tests/Fixtures/RecordingBackup", __dir__)
    original = JSON.parse(File.read(File.join(directory, "places-legacy.json")))
    expected = JSON.parse(File.read(File.join(directory, "places.json")))
    upgraded = upgrade_manifest(original)
    assert_equal expected, upgraded
    before = original.fetch("versionedHistoryRecords").first
    after = upgraded.fetch("versionedHistoryRecords").first
    assert_equal before.reject { |key, _| key == "scope" }, after.reject { |key, _| key == "scope" }
    assert_equal before.dig("scope", "periods"), after.dig("scope", "intervals")
    assert_equal original.fetch("versionedHistoryRecords").last, upgraded.fetch("versionedHistoryRecords").last
    assert_equal upgraded, upgrade_manifest(upgraded)
    assert_equal 8, original.fetch("formatVersion")
  end

  def test_v8_place_upgrade_requires_its_original_scope
    record = { "kind" => "recording.place", "semantics" => { "major" => 1 }, "scope" => { "entireHistory" => {} } }
    manifest = base_manifest(8).merge("versionedHistoryRecords" => [record])
    assert_raises(SystemExit) { upgrade_manifest(manifest) }
    assert_equal({ "entireHistory" => {} }, record.fetch("scope"))
  end

  def test_v8_place_upgrade_cannot_turn_missing_bounds_into_ongoing_validity
    fixture = File.expand_path("../../WhereCore/Tests/Fixtures/RecordingBackup/places-legacy.json", __dir__)
    original = JSON.parse(File.read(fixture))
    missing = Marshal.load(Marshal.dump(original))
    missing["versionedHistoryRecords"].first["scope"]["periods"]["_0"].first.delete("end")
    assert_raises(SystemExit) { upgrade_manifest(missing) }
    mismatched = Marshal.load(Marshal.dump(original))
    record = mismatched["versionedHistoryRecords"].first
    payload = JSON.parse(Base64.strict_decode64(record.fetch("payload")))
    payload["periods"].first.delete("end")
    record["payload"] = Base64.strict_encode64(JSON.generate(payload))
    assert_raises(SystemExit) { upgrade_manifest(mismatched) }
    assert_equal 8, original.fetch("formatVersion")
  end

  def test_public_command_upgrades_v8_place_zip_and_preserves_assets
    fixture = File.expand_path("../../WhereCore/Tests/Fixtures/RecordingBackup/places-legacy.json", __dir__)
    script = File.expand_path("../upgrade-backup.rb", __dir__)
    Dir.mktmpdir("place-upgrade") do |directory|
      source = File.join(directory, "source")
      FileUtils.mkdir_p(source)
      FileUtils.cp(fixture, File.join(source, "manifest.json"))
      File.binwrite(File.join(source, "evidence.bin"), "unchanged asset\0")
      input = File.join(directory, "input.zip")
      output = File.join(directory, "output.zip")
      assert system("zip", "-q", "-r", input, ".", chdir: source)
      original = File.binread(input)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, input, output)
      assert status.success?, stderr
      assert_includes stdout, output
      decoded, stderr, status = Open3.capture3("unzip", "-p", output, "manifest.json")
      assert status.success?, stderr
      assert_equal upgrade_manifest(JSON.parse(File.read(fixture))), JSON.parse(decoded)
      asset, stderr, status = Open3.capture3("unzip", "-p", output, "evidence.bin")
      assert status.success?, stderr
      assert_equal "unchanged asset\0", asset
      assert_equal original, File.binread(input)
    end
  end

  def test_v1_adds_current_tables_without_inventing_recording_consent
    upgraded = upgrade_manifest(base_manifest(1))

    assert_equal 9, upgraded.fetch("formatVersion")
    assert_equal [], upgraded.fetch("recordingDeviceProfiles")
    assert_equal [], upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal [], upgraded.fetch("recordingDeviceRemovals")
    assert_equal [], upgraded.fetch("plannedStayRecords")
    assert_equal [], upgraded.fetch("homeRegionRecords")
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

    assert_equal 9, upgraded.fetch("formatVersion")
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

  def test_v7_is_idempotent
    once = upgrade_manifest(base_manifest(7))
    assert_equal once, upgrade_manifest(Marshal.load(Marshal.dump(once)))
  end

  def test_v5_gains_empty_corrections_and_unknown_motion_without_altering_raw_fixes
    manifest = base_manifest(5)
    manifest["samples"] = [{ "id" => "sample", "timestamp" => 1000.25, "coordinate" => { "latitude" => 40, "longitude" => -100 } }]
    original = Marshal.load(Marshal.dump(manifest["samples"].first))

    upgraded = upgrade_manifest(manifest)

    assert_equal original.merge("recordingDeviceID" => nil, "motion" => nil, "timestamp" => original.fetch("timestamp") - 978_307_200), upgraded.fetch("samples").first
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
    manifest["plannedStayRecords"] = [{
      "id" => "stay-revision", "updatedAt" => Time.utc(2026, 9, 13).to_f, "value" => {
        "region" => "us-NY", "through" => { "year" => 2026, "month" => 10, "day" => 1 },
      },
    }, { "id" => "stay-deletion", "updatedAt" => Time.utc(2026, 9, 14).to_f }]

    upgraded = upgrade_manifest(manifest)

    assert_equal motion, upgraded.fetch("samples").first.fetch("motion")
    assert_equal convert_date_epoch!(Marshal.load(Marshal.dump(revisions))), upgraded.fetch("sampleAttributionRevisions")
    stays = upgraded.fetch("plannedStayRecords")
    assert_equal %w[stay-revision stay-deletion], stays.map { |record| record.fetch("id") }
    assert_equal [LEGACY_PLANNED_STAY_ID], stays.map { |record| record.fetch("stayID") }.uniq
    assert_equal({ "year" => 2026, "month" => 9, "day" => 13 }, stays.first.fetch("value").fetch("arrival").fetch("earliest"))
    assert_nil stays.last["value"]
    assert_equal [], upgraded.fetch("homeRegionRecords")
    assert_equal upgraded, upgrade_manifest(Marshal.load(Marshal.dump(upgraded)))
  end

  def test_verification_driver_counts_planned_stays_and_correction_tombstones
    manifest = upgrade_manifest(base_manifest(6))
    manifest["plannedStayRecords"] = [{ "id" => "stay", "value" => nil, "updatedAt" => 1000 }]
    manifest["sampleAttributionRevisions"] = [{ "id" => "reset", "sampleID" => "sample", "updatedAt" => 1001 }]
    manifest["homeRegionRecords"] = [{ "id" => "home-reset", "updatedAt" => 1002 }]
    driver = UpgradeAndVerify.new(["input.zip", "output.zip"])
    counts = driver.send(:expected_counts, manifest)
    configuration = driver.send(:verification_configuration, manifest)

    assert_equal 1, counts.fetch("plannedStayRecords")
    assert_equal 1, counts.fetch("homeRegionRecords")
    assert_equal 1, counts.fetch("sampleAttributionRevisions")
    assert_equal 1, configuration.fetch(:plannedStayRecordsCount)
    assert_equal 1, configuration.fetch(:homeRegionRecordsCount)
    assert_equal 1, configuration.fetch(:sampleAttributionRevisionsCount)
    manifest["sampleAttributionRevisions"] = []
    assert_raises(RuntimeError) { driver.send(:verify_counts!, manifest, counts) }
  end

  def test_verification_driver_passes_recording_map_and_counts_versioned_controls
    manifest = upgrade_manifest(base_manifest(7))
    manifest["requiredDataMajor"] = 1
    manifest["versionedHistoryRecords"] = [{ "payload" => "opaque" }]
    driver = UpgradeAndVerify.new(["input.zip", "output.zip", "--recording-map", "map.json"])
    assert_equal ["--recording-map", File.expand_path("map.json")], driver.send(:upgrader_command, "input.zip").last(2)
    assert_equal 1, driver.send(:expected_counts, manifest).fetch("versionedHistoryRecords")
    configuration = driver.send(:verification_configuration, manifest)
    assert_equal 1, configuration.fetch(:versionedHistoryRecordsCount)
    assert_equal 1, configuration.fetch(:requiredDataMajor)
  end

  def test_normalizes_legacy_iso8601_dates_to_foundation_reference_timestamps
    manifest = base_manifest(1)
    manifest["exportedAt"] = "2023-11-14T22:13:20Z"
    manifest["samples"].first["timestamp"] = "2023-11-14T22:15:00.500Z"

    upgraded = upgrade_manifest(manifest)

    assert_equal 1_700_000_000.0 - 978_307_200, upgraded.fetch("exportedAt")
    assert_equal 1_700_000_100.5 - 978_307_200, upgraded.fetch("samples").first.fetch("timestamp")
  end

  def test_rejects_future_formats
    error = assert_raises(SystemExit) { upgrade_manifest(base_manifest(10)) }
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
    assert_equal timestamp - 978_307_200, upgraded.first.fetch("updatedAt")
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
    assert_equal convert_date_epoch!(homes), upgraded.fetch("homeRegionRecords")
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
