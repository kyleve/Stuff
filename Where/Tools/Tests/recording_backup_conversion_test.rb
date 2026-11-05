# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../upgrade-backup"

class RecordingBackupConversionTest < Minitest::Test
  SAMPLE_ID = "11111111-1111-1111-1111-111111111111"
  DEVICE_ID = "22222222-2222-2222-2222-222222222222"

  def manifest
    { "formatVersion" => 7, "samples" => [{
      "id" => SAMPLE_ID, "timestamp" => Time.iso8601("2026-01-01T02:00:00Z").to_f,
      "source" => { "gpsVisit" => {} }, "horizontalAccuracy" => 12,
      "coordinate" => { "latitude" => 40, "longitude" => -74 },
    }], "assets" => [] }
  end

  def mapping
    { "samples" => { SAMPLE_ID => {
      "recordingDeviceID" => DEVICE_ID,
      "calendar" => { "timeZone" => "America/New_York", "secondsFromGMT" => -18_000 },
    } } }
  end

  def test_explicit_mapping_preserves_raw_fields_and_determines_logical_year
    original = manifest
    converted = upgrade_manifest(original, recording_map: mapping)
    sample = converted.fetch("samples").first
    assert_equal original.fetch("samples").first.merge("timestamp" => original.fetch("samples").first.fetch("timestamp") - 978_307_200), sample.slice(*original.fetch("samples").first.keys)
    assert_nil original.fetch("samples").first["recordingDeviceID"]
    assert_equal "store://devices/#{DEVICE_ID.downcase}", sample.fetch("recordingDeviceID")
    assert_equal 1, converted.fetch("requiredDataMajor")
    assert_equal({ "year" => 2025, "month" => 12, "day" => 31 }, sample.dig("recordingDay", "resolved", "_0", "day"))
    assert_equal converted, upgrade_manifest(converted, recording_map: mapping)
    another_archive = manifest.merge("exportedAt" => 2_000_000_000)
    assert_equal sample, upgrade_manifest(another_archive, recording_map: mapping).fetch("samples").first
  end

  def test_missing_device_and_missing_calendar_are_rejected_without_mutating_source
    original = manifest
    [ { "samples" => {} }, { "samples" => { SAMPLE_ID => { "recordingDeviceID" => DEVICE_ID } } } ].each do |map|
      assert_raises(ArgumentError) { upgrade_manifest(original, recording_map: map) }
      assert_equal manifest, original
    end
  end

  def test_unknown_calendar_is_explicit_and_manual_samples_remain_device_agnostic
    map = mapping
    map["samples"][SAMPLE_ID]["calendar"] = { "unresolved" => true }
    original = manifest
    manual = original["samples"].first.merge("id" => "manual", "source" => { "manual" => {} })
    original["samples"] << manual
    samples = upgrade_manifest(original, recording_map: map).fetch("samples")
    assert_equal({ "unresolved" => {} }, samples.first.fetch("recordingDay"))
    assert_nil samples.last["recordingDeviceID"]
    assert_nil samples.last["recordingDay"]
  end

  def test_existing_attribution_and_context_cannot_be_changed_by_mapping
    converted = upgrade_manifest(manifest, recording_map: mapping)
    changed_device = mapping
    changed_device["samples"][SAMPLE_ID]["recordingDeviceID"] = "33333333-3333-3333-3333-333333333333"
    assert_raises(ArgumentError) { upgrade_manifest(converted, recording_map: changed_device) }
    changed_calendar = mapping
    changed_calendar["samples"][SAMPLE_ID]["calendar"]["secondsFromGMT"] = 0
    assert_raises(ArgumentError) { upgrade_manifest(converted, recording_map: changed_calendar) }
  end

  def test_saved_offset_is_authoritative_even_when_current_tzdb_would_disagree
    map = mapping
    map["samples"][SAMPLE_ID]["calendar"]["secondsFromGMT"] = 3600
    context = upgrade_manifest(manifest, recording_map: map).dig("samples", 0, "recordingDay", "resolved", "_0")
    assert_equal({ "year" => 2026, "month" => 1, "day" => 1 }, context.fetch("day"))
    assert_equal 3600, context.fetch("secondsFromGMT")
  end

  def test_rejects_bad_offset_zone_and_future_contract_without_lowering_floor
    [100_000, 0.5].each do |offset|
      map = mapping
      map["samples"][SAMPLE_ID]["calendar"]["secondsFromGMT"] = offset
      assert_raises(ArgumentError) { upgrade_manifest(manifest, recording_map: map) }
    end
    map = mapping
    map["samples"][SAMPLE_ID]["calendar"]["timeZone"] = "../../etc/passwd"
    assert_raises(ArgumentError) { upgrade_manifest(manifest, recording_map: map) }
    future = upgrade_manifest(manifest).merge("requiredDataMajor" => 2)
    assert_raises(ArgumentError) { upgrade_manifest(future, recording_map: mapping) }
  end

  def test_shared_swift_fixture_matches_the_production_converter
    directory = File.expand_path("../../WhereCore/Tests/Fixtures/RecordingBackup", __dir__)
    original = JSON.parse(File.read(File.join(directory, "legacy.json")))
    map = JSON.parse(File.read(File.join(directory, "mapping.json")))
    expected = JSON.parse(File.read(File.join(directory, "converted.json")))
    assert_equal expected, upgrade_manifest(original, recording_map: map)
    historical = JSON.parse(File.read(File.join(directory, "historical-legacy.json")))
    historical_map = JSON.parse(File.read(File.join(directory, "historical-mapping.json")))
    historical_expected = JSON.parse(File.read(File.join(directory, "historical.json")))
    assert_equal historical_expected, upgrade_manifest(historical, recording_map: historical_map)
    boundary = JSON.parse(File.read(File.join(directory, "epoch-boundary-legacy.json")))
    boundary_map = JSON.parse(File.read(File.join(directory, "epoch-boundary-mapping.json")))
    boundary_expected = JSON.parse(File.read(File.join(directory, "epoch-boundary.json")))
    converted = upgrade_manifest(boundary, recording_map: boundary_map)
    assert_equal boundary_expected, converted
    assert_equal(-978_307_200.0, converted.dig("samples", 0, "timestamp"))
    assert_equal({ "year" => 1970, "month" => 1, "day" => 1 }, converted.dig("samples", 0, "recordingDay", "resolved", "_0", "day"))
    assert_equal converted, upgrade_manifest(converted, recording_map: boundary_map)
  end

  def test_zero_offset_aliases_match_foundation_canonical_names
    ["UTC", "GMT+0000", "GMT-0000"].each do |zone|
      map = mapping
      map["samples"][SAMPLE_ID]["calendar"] = { "timeZone" => zone, "secondsFromGMT" => 0 }
      converted = upgrade_manifest(manifest, recording_map: map)
      assert_equal "GMT", converted.dig("samples", 0, "recordingDay", "resolved", "_0", "timeZone", "identifier")
      assert_equal converted, upgrade_manifest(converted, recording_map: map)
    end
  end

  def test_existing_fixed_offset_context_survives_reconversion
    map = mapping
    map["samples"][SAMPLE_ID]["calendar"] = { "timeZone" => "GMT+0100", "secondsFromGMT" => 3600 }
    converted = upgrade_manifest(manifest, recording_map: map)
    assert_equal converted, upgrade_manifest(converted, recording_map: { "samples" => {} })
    refute RecordingBackupConversion.valid_zone_identifier?("GMT+1830")
    refute RecordingBackupConversion.valid_zone_identifier?("GMT+0099")
  end

  def test_public_command_rejects_directory_output_without_removing_its_contents
    Dir.mktmpdir("recording backup directory") do |directory|
      input = File.join(directory, "input.zip")
      File.write(input, "input stays intact")
      output = File.join(directory, "valuable directory")
      Dir.mkdir(output)
      kept = File.join(output, "keep.txt")
      File.write(kept, "keep this")
      _, stderr, status = Open3.capture3(RbConfig.ruby, File.expand_path("../upgrade-backup.rb", __dir__), input, output)
      refute status.success?
      assert_includes stderr, "output must be a regular file"
      assert_equal "keep this", File.read(kept)
      assert_equal "input stays intact", File.read(input)
    end
  end

  def test_public_command_preserves_input_assets_and_existing_output_on_bad_mapping
    Dir.mktmpdir("recording backup – ") do |directory|
      contents = File.join(directory, "contents")
      FileUtils.mkdir_p(File.join(contents, "assets"))
      File.write(File.join(contents, "manifest.json"), JSON.generate(manifest))
      File.binwrite(File.join(contents, "assets", "evidence"), "\x00\xff\x01")
      input = File.join(directory, "original.zip")
      output = File.join(directory, "converted.zip")
      assert system("zip", "-q", "-r", input, ".", chdir: contents)
      input_bytes = File.binread(input)
      File.write(output, "retained output")
      mapping_path = File.join(directory, "mapping.json")
      File.write(mapping_path, JSON.generate({ "samples" => {} }))
      command = [RbConfig.ruby, File.expand_path("../upgrade-backup.rb", __dir__), input, output, "--recording-map", mapping_path]
      _, stderr, status = Open3.capture3(*command, chdir: directory)
      refute status.success?
      assert_includes stderr, "recording device"
      assert_equal "retained output", File.read(output)
      assert_equal input_bytes, File.binread(input)
      File.write(mapping_path, JSON.generate(mapping))
      stdout, stderr, status = Open3.capture3(*command, chdir: directory)
      assert status.success?, stderr
      assert_equal output, stdout.lines.last.strip
      archive, status = Open3.capture2("unzip", "-p", output, "manifest.json")
      assert status.success?
      assert_equal upgrade_manifest(manifest, recording_map: mapping), JSON.parse(archive)
      bytes, status = Open3.capture2("unzip", "-p", output, "assets/evidence", binmode: true)
      assert status.success?
      assert_equal "\x00\xff\x01".b, bytes
      assert_equal input_bytes, File.binread(input)
    end
  end
end
