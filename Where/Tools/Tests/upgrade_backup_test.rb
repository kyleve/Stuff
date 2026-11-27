# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../upgrade-backup"
require_relative "../../../.agents/skills/upgrade-where-backup/scripts/upgrade_and_verify"

class UpgradeBackupTest < Minitest::Test
  PHONE = "store://devices/65000000-0000-0000-0000-000000000001"
  TABLET = "store://devices/65000000-0000-0000-0000-000000000002"
  SAMPLE = "70000000-0000-0000-0000-000000000001"
  SECOND_SAMPLE = "70000000-0000-0000-0000-000000000002"
  GENERATION = { "rawValue" => "00000000-0000-0000-0000-0000000000E0" }.freeze

  def test_v1_adds_current_tables_without_inventing_recording_consent
    upgraded = upgrade_manifest(base_manifest(1))

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
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
      "recordingDeviceProfiles" => [profile.except("registrationGenerationID").merge("kind" => "other", "registrationEpochID" => GENERATION.dup)],
      "recordingDeviceMetadataChanges" => [{
        "field" => "nickname", "deviceID" => PHONE, "changedByDeviceID" => PHONE,
        "nickname" => "Travel iPad",
      }, {
        "field" => "nickname", "deviceID" => PHONE, "changedByDeviceID" => PHONE,
      }],
    )

    upgraded = upgrade_manifest(manifest)

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
    assert_equal profile.merge("kind" => { "other" => {} }), upgraded.fetch("recordingDeviceProfiles").first
    assert_equal({
      "deviceID" => PHONE, "changedByDeviceID" => PHONE,
      "payload" => { "field" => "nickname", "nickname" => "Travel iPad" },
    }, upgraded.fetch("recordingDeviceMetadataChanges").first)
    assert_equal({
      "deviceID" => PHONE, "changedByDeviceID" => PHONE,
      "payload" => { "field" => "nickname" },
    }, upgraded.fetch("recordingDeviceMetadataChanges").last)
  end

  def test_released_v7_and_v8_preserve_manual_only_canadian_history
    legacy = base_manifest(7).merge(
      "samples" => [],
      "manualDays" => [
        { "day" => { "year" => 2026, "month" => 7, "day" => 1 }, "regions" => %w[us-CA canada], "isAuthoritative" => true },
      ],
      "primaryRegions" => [{ "region" => "canada", "order" => 0 }],
      "recordingDeviceProfiles" => [], "recordingDeviceMetadataChanges" => [], "recordingDeviceRemovals" => [],
      "plannedStayRecords" => [], "homeRegionRecords" => [], "sampleAttributionRevisions" => [],
    )
    upgraded = upgrade_manifest(Marshal.load(Marshal.dump(legacy)))
    assert_equal legacy.merge("formatVersion" => CURRENT_FORMAT_VERSION), upgraded
    ontario = Marshal.load(Marshal.dump(legacy)).merge("formatVersion" => 8)
    ontario.fetch("manualDays").first.fetch("regions") << "ca-ON"
    assert_equal ontario.merge("formatVersion" => CURRENT_FORMAT_VERSION), upgrade_manifest(ontario)
    assert_empty upgraded.fetch("recordingDeviceProfiles")
    assert_equal upgraded, upgrade_manifest(Marshal.load(Marshal.dump(upgraded)))
    obsolete = { "recordingDevices" => ["old-device"], "recordingDeviceCheckIns" => ["old-check-in"], "recordingPolicyChanges" => ["old-policy"] }
    assert_equal legacy.merge("formatVersion" => CURRENT_FORMAT_VERSION), upgrade_manifest(legacy.merge(obsolete))
    assert_equal upgraded, upgrade_manifest(upgraded.merge(obsolete))
  end

  def test_v5_gains_empty_corrections_and_unknown_motion_without_altering_raw_fixes
    manifest = base_manifest(5)
    manifest["samples"] = [gps_sample.merge("timestamp" => 1000.25)]
    original = Marshal.load(Marshal.dump(manifest["samples"].first))

    upgraded = upgrade_manifest(manifest, source_profile: profile)

    assert_equal original.merge("recordingDeviceID" => PHONE, "motion" => nil), upgraded.fetch("samples").first
    assert_equal [], upgraded.fetch("sampleAttributionRevisions")
  end

  def test_v6_preserves_motion_and_every_correction_revision_including_tombstones
    motion = {
      "speed" => { "metersPerSecond" => 240, "accuracyMetersPerSecond" => 2 },
      "altitude" => { "meters" => 11000, "accuracyMeters" => 12 },
    }
    revisions = [nil, [], ["us-NY"]].each_with_index.map do |regions, index|
      { "id" => format("80000000-0000-0000-0000-%012d", index), "sampleID" => SAMPLE, "updatedAt" => 1000 + index, "replacementRegions" => regions }
    end
    manifest = base_manifest(6).merge("sampleAttributionRevisions" => Marshal.load(Marshal.dump(revisions)))
    manifest["samples"] = [gps_sample.merge("recordingDeviceID" => PHONE)]
    manifest["samples"].first["motion"] = motion
    manifest["plannedStayRecords"] = [{
      "id" => "stay-revision", "updatedAt" => Time.utc(2026, 9, 13).to_f, "value" => {
        "region" => "us-NY", "through" => { "year" => 2026, "month" => 10, "day" => 1 },
      },
    }, { "id" => "stay-deletion", "updatedAt" => Time.utc(2026, 9, 14).to_f }]

    upgraded = upgrade_manifest(manifest)

    assert_equal motion, upgraded.fetch("samples").first.fetch("motion")
    assert_equal revisions.map { |revision| revision.merge("changedByDeviceID" => PHONE) }, upgraded.fetch("sampleAttributionRevisions")
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

  def test_normalizes_legacy_iso8601_dates_to_current_unix_timestamps
    manifest = base_manifest(1)
    manifest["exportedAt"] = "2023-11-14T22:13:20Z"
    manifest["samples"].first["timestamp"] = "2023-11-14T22:15:00.500Z"

    upgraded = upgrade_manifest(manifest)

    assert_equal 1_700_000_000.0, upgraded.fetch("exportedAt")
    assert_equal 1_700_000_100.5, upgraded.fetch("samples").first.fetch("timestamp")
  end

  def test_rejects_future_formats
    error = assert_rejected { upgrade_manifest(base_manifest(CURRENT_FORMAT_VERSION + 1)) }
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

    error = assert_rejected { upgrade_manifest(manifest) }
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

  def test_supports_missing_gps_origin_across_every_legacy_shape
    (1..8).each do |version|
      manifest = version >= 7 ? modern_manifest(version) : base_manifest(version)
      manifest["samples"] = [gps_sample]
      result = upgrade_manifest(manifest, source_profile: profile)
      assert_equal PHONE, result.fetch("samples").first.fetch("recordingDeviceID")
      assert_equal [profile], result.fetch("recordingDeviceProfiles")
      assert_equal result, upgrade_manifest(Marshal.load(Marshal.dump(result)), source_profile: profile)
    end
    prototype = base_manifest(7).merge("samples" => [gps_sample], "trackedRegions" => ["california"])
    result = upgrade_manifest(prototype, source_profile: profile)
    assert_equal PHONE, result.fetch("samples").first.fetch("recordingDeviceID")
    assert_equal [{ "region" => "us-CA", "appearance" => nil, "order" => 0 }], result.fetch("primaryRegions")
  end

  def test_infers_single_origin_from_profile_or_stamped_fix_and_keeps_known_fields
    [true, false].each do |include_profile|
      manifest = modern_manifest(8)
      manifest["recordingDeviceProfiles"] = [profile] if include_profile
      manifest["samples"] = [gps_sample.merge("recordingDeviceID" => PHONE), gps_sample.merge("id" => SECOND_SAMPLE)]
      manifest["sampleAttributionRevisions"] = [revision.merge("sampleID" => SECOND_SAMPLE, "updatedAt" => 50)]
      result = upgrade_manifest(manifest)
      assert_equal [PHONE, PHONE], result.fetch("samples").map { |sample| sample.fetch("recordingDeviceID") }
      assert_equal PHONE, result.fetch("sampleAttributionRevisions").first.fetch("changedByDeviceID")
      assert_equal include_profile ? [profile] : [], result.fetch("recordingDeviceProfiles")
    end
  end

  def test_original_source_mapping_preserves_distinct_known_authors_and_capture_ids
    manifest = modern_manifest(8)
    manifest["samples"] = [gps_sample.merge("recordingDeviceID" => TABLET), gps_sample.merge("id" => SECOND_SAMPLE)]
    manifest["recordingDeviceProfiles"] = [profile]
    manifest["sampleAttributionRevisions"] = [
      revision.merge("changedByDeviceID" => TABLET), revision.merge("id" => SECOND_SAMPLE),
    ]
    assert_rejected { upgrade_manifest(Marshal.load(Marshal.dump(manifest))) }
    upgraded = upgrade_manifest(manifest, source_profile: { "id" => PHONE })
    assert_equal [TABLET, PHONE], upgraded.fetch("samples").map { |row| row.fetch("recordingDeviceID") }
    assert_equal [TABLET, PHONE], upgraded.fetch("sampleAttributionRevisions").map { |row| row.fetch("changedByDeviceID") }
    assert_equal [profile], upgraded.fetch("recordingDeviceProfiles")
  end

  def test_explicitly_selects_an_observed_id_before_its_profile_arrives
    manifest = modern_manifest(8).merge(
      "samples" => [gps_sample.merge("recordingDeviceID" => PHONE)],
      "sampleAttributionRevisions" => [revision.merge("id" => SECOND_SAMPLE, "changedByDeviceID" => TABLET), revision],
    )
    selected = { "id" => PHONE }
    source = Marshal.load(Marshal.dump(manifest))
    result = upgrade_manifest(manifest, source_profile: selected)
    assert_equal [TABLET, PHONE], result.fetch("sampleAttributionRevisions").map { |row| row.fetch("changedByDeviceID") }
    assert_empty result.fetch("recordingDeviceProfiles")
    driver = UpgradeAndVerify.new(["input.zip", "output.zip"])
    refute driver.send(:added_source_profile?, selected, source, result)
  end

  def test_device_events_prevent_guessing_from_a_single_visible_profile
    manifest = modern_manifest(8).merge(
      "recordingDeviceProfiles" => [profile],
      "recordingDeviceRemovals" => [{ "deviceID" => PHONE, "removedByDeviceID" => TABLET }],
      "sampleAttributionRevisions" => [revision],
    )
    assert_rejected { upgrade_manifest(manifest) }
    assert_equal PHONE, upgrade_manifest(manifest, source_profile: { "id" => PHONE })
      .fetch("sampleAttributionRevisions").first.fetch("changedByDeviceID")
  end

  def test_missing_origin_on_a_duplicate_uses_the_same_record_even_with_two_devices
    rows = [gps_sample, gps_sample.merge("recordingDeviceID" => TABLET)]
    manifest = modern_manifest(8).merge("recordingDeviceProfiles" => [profile], "samples" => rows)
    result = upgrade_manifest(manifest, source_profile: { "id" => PHONE })
    assert_equal [TABLET, TABLET], result.fetch("samples").map { |row| row.fetch("recordingDeviceID") }
    assert_equal [profile], result.fetch("recordingDeviceProfiles")
  end

  def test_overlapping_archives_use_one_supplied_immutable_profile_and_skip_unrelated_archives
    source = modern_manifest(8).merge("samples" => [gps_sample])
    driver = UpgradeAndVerify.new(["input.zip", "output.zip"])
    [100, 200].each do |time|
      result = upgrade_manifest(Marshal.load(Marshal.dump(source)).merge("exportedAt" => time), source_profile: profile)
      assert_equal [profile], result.fetch("recordingDeviceProfiles")
      assert driver.send(:added_source_profile?, profile, source, result)
      result.fetch("recordingDeviceProfiles").clear
      assert_raises(RuntimeError) { driver.send(:added_source_profile?, profile, source, result) }
    end
    empty = modern_manifest(8).merge("samples" => [])
    assert_empty upgrade_manifest(empty, source_profile: profile).fetch("recordingDeviceProfiles")
  end

  def test_profileless_legacy_record_requires_a_complete_original_profile
    manifest = modern_manifest(8).merge("samples" => [gps_sample])
    assert_rejected { upgrade_manifest(manifest) }
    assert_rejected { upgrade_manifest(manifest, source_profile: { "id" => PHONE }) }
    assert_rejected { upgrade_manifest(manifest, source_profile: profile.except("registeredAt")) }
    assert_rejected { upgrade_manifest(manifest, source_profile: profile.merge("id" => "not-a-device")) }
  end

  def test_rejects_conflicting_profiles_even_when_the_archive_has_no_missing_origins
    manifest = modern_manifest(8).merge("recordingDeviceProfiles" => [profile])
    another = profile.merge("systemName" => "different")
    assert_rejected { upgrade_manifest(manifest, source_profile: another) }
    manifest.fetch("recordingDeviceProfiles") << another
    assert_rejected { upgrade_manifest(manifest) }
  end

  def test_keeps_manual_and_evidence_sources_and_their_existing_device_ids
    samples = [
      gps_sample.merge("source" => { "manual" => {} }, "recordingDeviceID" => TABLET),
      gps_sample.merge("id" => SECOND_SAMPLE, "source" => { "evidenceImplied" => { "id" => SAMPLE, "kind" => { "photo" => {} } } }),
    ]
    result = upgrade_manifest(modern_manifest(8).merge("samples" => Marshal.load(Marshal.dump(samples))), source_profile: profile)
    assert_equal samples, result.fetch("samples")
    assert_empty result.fetch("recordingDeviceProfiles")
  end

  def test_zip_keeps_original_archive_and_all_evidence_bytes_even_after_a_failed_conversion
    Dir.mktmpdir do |work|
      input = File.join(work, "original.zip")
      output = File.join(work, "converted.zip")
      mapping = File.join(work, "phone.json")
      File.write(mapping, JSON.generate(profile))
      asset_bytes = "\x00\xff\x08synthetic".b
      manifest = modern_manifest(8).merge(
        "samples" => [gps_sample],
        "assets" => [{ "evidenceId" => SAMPLE, "filename" => "assets/proof" }],
      )
      Dir.mktmpdir do |staging|
        FileUtils.mkdir(File.join(staging, "assets"))
        File.binwrite(File.join(staging, "assets/proof"), asset_bytes)
        File.write(File.join(staging, "manifest.json"), JSON.generate(manifest))
        assert system("zip", "-q", "-r", input, ".", chdir: staging)
      end
      original = File.binread(input)
      capture_io { main([input, output, "--source-profile", mapping]) }
      verified = File.binread(output)
      assert_equal original, File.binread(input)
      assert_equal asset_bytes, Open3.capture3("unzip", "-p", output, "assets/proof", binmode: true).first
      assert_equal PHONE, JSON.parse(Open3.capture3("unzip", "-p", output, "manifest.json").first).fetch("samples").first.fetch("recordingDeviceID")
      assert_rejected { main([input, output]) }
      assert_equal verified, File.binread(output)
      assert_rejected { main([input, input, "--source-profile", mapping]) }
      assert_equal original, File.binread(input)
    end
  end

  def test_duplicate_sample_identity_matches_swift_persistence_including_evidence_links
    gps = gps_sample.merge("recordingDeviceID" => PHONE)
    evidence = lambda do |id, kind|
      gps_sample.merge("source" => { "evidenceImplied" => { "id" => id, "kind" => kind } })
    end
    labeled = evidence.call(SAMPLE, { "other" => { "_0" => "ticket" } })
    unlabeled = evidence.call(SAMPLE, { "other" => {} })
    manifest = modern_manifest(CURRENT_FORMAT_VERSION)
    [[gps, gps.merge("timestamp" => 5)], [labeled, unlabeled]].each do |samples|
      assert_equal samples, upgrade_manifest(manifest.merge("samples" => samples)).fetch("samples")
    end
    [
      [gps, gps.merge("source" => { "gpsSignificantChange" => {} })],
      [gps, gps.merge("source" => { "manual" => {} })],
      [labeled, evidence.call(SECOND_SAMPLE, { "other" => {} })],
      [labeled, evidence.call(SAMPLE, { "photo" => {} })],
    ].each do |samples|
      assert_rejected { upgrade_manifest(manifest.merge("samples" => samples)) }
    end
  end

  def test_repeated_revisions_require_same_sample_timestamp_author_and_optional_region_set
    base = revision.merge("changedByDeviceID" => PHONE, "replacementRegions" => %w[ca-ON us-NY])
    manifest = modern_manifest(CURRENT_FORMAT_VERSION)
    [base.merge("sampleID" => SECOND_SAMPLE), base.merge("changedByDeviceID" => TABLET),
     base.merge("updatedAt" => 6), base.merge("replacementRegions" => nil), base.merge("replacementRegions" => [])].each do |conflict|
      assert_rejected { upgrade_manifest(manifest.merge("sampleAttributionRevisions" => [base, conflict])) }
    end
    identical = base.merge("replacementRegions" => %w[us-NY ca-ON ca-ON])
    rows = [base, identical]
    assert_equal rows, upgrade_manifest(manifest.merge("sampleAttributionRevisions" => rows)).fetch("sampleAttributionRevisions")
    assert_rejected do
      upgrade_manifest(manifest.merge("sampleAttributionRevisions" => [base.except("replacementRegions"), base.merge("replacementRegions" => [])]))
    end
  end

  def test_current_archive_provenance_is_validated_without_backfilling
    invalid = [
      { "samples" => [gps_sample] },
      { "samples" => [gps_sample.merge("recordingDeviceID" => "incorrect")] },
      { "sampleAttributionRevisions" => [revision.merge("changedByDeviceID" => nil)] },
      { "samples" => [gps_sample.merge("recordingDeviceID" => PHONE), gps_sample.merge("recordingDeviceID" => TABLET)] },
      { "sampleAttributionRevisions" => [PHONE, TABLET].map { |id| revision.merge("changedByDeviceID" => id) } },
    ]
    invalid.each do |fields|
      assert_rejected { upgrade_manifest(modern_manifest(CURRENT_FORMAT_VERSION).merge(fields), source_profile: profile) }
    end
    known = modern_manifest(CURRENT_FORMAT_VERSION).merge("sampleAttributionRevisions" => [revision.merge("changedByDeviceID" => TABLET)])
    assert_equal known, upgrade_manifest(known)
  end

  private

  def assert_rejected(&operation)
    rejected = nil
    _stdout, stderr = capture_io { rejected = assert_raises(SystemExit, &operation) }
    assert_includes stderr, "error:"
    rejected
  end

  def gps_sample
    {
      "id" => SAMPLE, "timestamp" => 0, "horizontalAccuracy" => 5,
      "coordinate" => { "latitude" => 40, "longitude" => -100 }, "source" => { "gpsVisit" => {} },
    }
  end

  def revision
    { "id" => "80000000-0000-0000-0000-000000000001", "sampleID" => SAMPLE, "updatedAt" => 5 }
  end

  def profile
    {
      "id" => PHONE, "systemName" => "Original iPhone", "kind" => { "phone" => {} },
      "registeredAt" => 0, "registrationGenerationID" => GENERATION,
    }
  end

  def modern_manifest(version)
    MANIFEST_COLLECTIONS.to_h { |key| [key, []] }.merge("formatVersion" => version, "exportedAt" => 0)
  end

  def base_manifest(version)
    {
      "formatVersion" => version,
      "exportedAt" => 0.0,
      "samples" => [gps_sample.merge("source" => { "manual" => {} })],
      "evidence" => [],
      "manualDays" => [],
      "dismissedIssues" => [],
      "trackedRegions" => [],
      "assets" => [],
    }
  end
end
