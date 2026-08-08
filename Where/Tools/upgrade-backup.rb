#!/usr/bin/env ruby
# frozen_string_literal: true

# Reshapes a legacy Where backup into the current v4 manifest. The automatic-recording feature
# was not shipped in v1 or v2, so upgrading adds the recording tables empty; it never invents an
# installation or recording consent. v4 gives device kinds and metadata edits rename-safe shapes.

require "json"
require "tmpdir"
require "fileutils"
require "time"
require "set"

MANIFEST_NAME = "manifest.json"
CURRENT_FORMAT_VERSION = 4
SUPPORTED_SOURCE_FORMAT_VERSIONS = (1..CURRENT_FORMAT_VERSION).freeze

REGION_MAP = {
  "california" => "us-CA",
  "newYork" => "us-NY",
  "europeanUnion" => "european-union",
  "canada" => "canada",
  "other" => "other",
}.freeze

ISSUE_PARAM_NAMES = {
  "missingDays" => %w[start],
  "borderDrift" => %w[day],
  "abruptChange" => %w[earlier later],
}.freeze

DATE_KEYS = %w[
  exportedAt timestamp capturedAt dismissedAt registeredAt changedAt removedAt recordedAt
  lastSeenAt auditRecordedAt auditLocationTimestamp
].to_set.freeze

def die(message)
  warn "error: #{message}"
  exit 1
end

def print_usage
  puts <<~USAGE
    Usage: ruby Where/Tools/upgrade-backup.rb INPUT.zip [OUTPUT.zip]

    Upgrades a Where backup export to the current manifest shape.
    OUTPUT defaults to INPUT-upgraded.zip.
  USAGE
end

def catalog_region_ids
  path = File.expand_path("../RegionKit/Sources/Resources/regions.json", __dir__)
  die "regions.json not found at #{path}" unless File.exist?(path)
  (JSON.parse(File.read(path)).map { |entry| entry.fetch("id") } + ["other"]).to_set
end

VALID_REGION_IDS = catalog_region_ids

def recovered_day_iso(instant_seconds)
  time = Time.at(instant_seconds + (12 * 60 * 60)).utc
  format("%04d-%02d-%02d", time.year, time.month, time.day)
end

def value_to_day_iso(value)
  case value
  when /\A\d{4}-\d{2}-\d{2}\z/
    value
  when /\A\d+(?:\.\d+)?\z/
    recovered_day_iso(value.to_f)
  else
    recovered_day_iso(Time.iso8601(value).to_f)
  end
rescue ArgumentError
  die "could not parse day value: #{value.inspect}"
end

def rekey_region(id, warnings)
  return id if id.nil?

  mapped = REGION_MAP.fetch(id, id)
  warnings << "unknown region id #{mapped.inspect}; the app may reject this archive" unless VALID_REGION_IDS.include?(mapped)
  mapped
end

def upgrade_evidence!(manifest, warnings)
  Array(manifest["evidence"]).each do |item|
    item["region"] = rekey_region(item["region"], warnings) if item.key?("region")
  end
end

def upgrade_manual_days!(manifest, warnings)
  Array(manifest["manualDays"]).each do |day|
    unless day.key?("day")
      iso = value_to_day_iso(day.delete("date"))
      year, month, day_number = iso.split("-").map(&:to_i)
      day["day"] = { "year" => year, "month" => month, "day" => day_number }
    end
    day["regions"] = Array(day["regions"]).map { |id| rekey_region(id, warnings) }
    day["isAuthoritative"] = false unless day.key?("isAuthoritative")
  end
end

def issue_store_url(type, values)
  names = ISSUE_PARAM_NAMES[type]
  die "unknown dismissed issue type #{type.inspect}" unless names
  die "dismissed issue #{type.inspect} expected #{names.length} value(s)" unless values.length == names.length

  query = names.zip(values).map { |name, value| "#{name}=#{value_to_day_iso(value)}" }.join("&")
  "store://issues/#{type}?#{query}"
end

def upgrade_dismissals!(manifest)
  Array(manifest["dismissedIssues"]).each do |dismissal|
    next if dismissal.key?("id")

    key = dismissal.delete("key")
    type, *values = key.to_s.split(":")
    dismissal["id"] = issue_store_url(type, values)
  end
end

def normalize_dates!(value)
  case value
  when Hash
    value.each do |key, child|
      value[key] = if DATE_KEYS.include?(key) && child.is_a?(String)
        Time.iso8601(child).to_f
      else
        normalize_dates!(child)
      end
    rescue ArgumentError
      die "could not parse date value for #{key}: #{child.inspect}"
    end
  when Array
    value.each { |child| normalize_dates!(child) }
  end
  value
end

def upgrade_recording_devices!(manifest, source_version)
  return unless source_version < 4

  Array(manifest["recordingDeviceProfiles"]).each do |profile|
    kind = profile["kind"]
    profile["kind"] = { "kind" => kind } if kind.is_a?(String)
    if profile.key?("registrationEpochID")
      profile["registrationGenerationID"] = profile.delete("registrationEpochID")
    end
  end

  Array(manifest["recordingDeviceMetadataChanges"]).each do |change|
    next if change.key?("payload")

    payload = { "field" => change.delete("field") }
    payload["nickname"] = change.delete("nickname") if change.key?("nickname")
    change["payload"] = payload
  end
end

def source_format_version(manifest)
  version = manifest["formatVersion"]
  die "manifest formatVersion must be an integer" unless version.is_a?(Integer)
  unless SUPPORTED_SOURCE_FORMAT_VERSIONS.cover?(version)
    die "unsupported manifest formatVersion #{version}; expected 1-#{CURRENT_FORMAT_VERSION}"
  end
  version
end

def upgrade_manifest(manifest)
  source_version = source_format_version(manifest)
  warnings = []
  upgrade_evidence!(manifest, warnings)
  upgrade_manual_days!(manifest, warnings)
  upgrade_dismissals!(manifest)
  normalize_dates!(manifest)
  manifest["dismissedIssues"] ||= []
  manifest["trackedRegions"] ||= []
  manifest["trackedRegions"] = manifest["trackedRegions"].map do |id|
    rekey_region(id, warnings)
  end
  manifest["primaryRegions"] ||= manifest["trackedRegions"].each_with_index.map do |id, index|
    { "region" => id, "appearance" => nil, "order" => index }
  end
  Array(manifest["samples"]).each do |sample|
    sample["recordingDeviceID"] = nil unless sample.key?("recordingDeviceID")
  end

  manifest["recordingDeviceProfiles"] ||= []
  manifest["recordingDeviceMetadataChanges"] ||= []
  manifest["recordingDeviceRemovals"] ||= []
  upgrade_recording_devices!(manifest, source_version)
  manifest.delete("recordingDevices")
  manifest.delete("recordingDeviceCheckIns")
  manifest.delete("recordingPolicyChanges")
  manifest["formatVersion"] = CURRENT_FORMAT_VERSION
  warnings.uniq.each { |message| warn "warning: #{message}" }
  manifest
end

def run_or_die(*command)
  return if system(*command)

  die "command failed: #{command.join(' ')}"
end

def sort_deep(value)
  case value
  when Hash
    value.keys.sort.to_h { |key| [key, sort_deep(value[key])] }
  when Array
    value.map { |item| sort_deep(item) }
  else
    value
  end
end

def main(argv)
  if argv.empty? || argv.include?("--help") || argv.include?("-h")
    print_usage
    exit(argv.empty? ? 1 : 0)
  end

  input = argv[0]
  die "input not found: #{input}" unless File.exist?(input)
  output = File.expand_path(argv[1] || input.sub(/(\.zip)?\z/i, "-upgraded.zip"))

  Dir.mktmpdir("where-backup-upgrade") do |work|
    run_or_die("unzip", "-q", File.expand_path(input), "-d", work)
    manifest_path = File.join(work, MANIFEST_NAME)
    die "#{MANIFEST_NAME} not found in archive (is this a Where backup?)" unless File.exist?(manifest_path)

    manifest = JSON.parse(File.read(manifest_path))
    File.write(manifest_path, JSON.pretty_generate(sort_deep(upgrade_manifest(manifest))) + "\n")
    FileUtils.rm_f(output)
    Dir.chdir(work) { run_or_die("zip", "-q", "-r", output, ".") }
  end
  puts output
end

main(ARGV) if $PROGRAM_NAME == __FILE__
