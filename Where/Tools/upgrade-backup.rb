#!/usr/bin/env ruby
# frozen_string_literal: true

# Upgrades an exported Where backup `.zip` to the current manifest shape so it
# can be re-imported after the Codable / legacy-field cleanup.
#
# The app no longer migrates old data on read (see
# `Where/WhereCore/AGENTS.md`), so an export produced by an older build must be
# reshaped once, out of band, before import. This script does exactly that,
# rewriting `manifest.json` inside the archive and leaving `assets/` untouched:
#
#   - Region ids: rekeys the former enum-case ids to catalog ids
#     (`california` -> `us-CA`, `newYork` -> `us-NY`,
#      `europeanUnion` -> `european-union`; `canada` / `other` unchanged),
#     across evidence, manual days, and tracked regions. Warns on any id it
#     can't map to a real catalog region.
#   - Manual days: converts a legacy absolute `date` instant to a
#     timezone-independent `day` (`{year,month,day}`), recovering the calendar
#     day the writer meant (UTC, +12h nudge — matching the app's former
#     recovery), and ensures `isAuthoritative` is present (default `false`).
#   - Dismissals: converts `{ "key": "borderDrift:2026-04-01", ... }` to
#     `{ "id": "store://issues/borderDrift?day=2026-04-01", ... }`, parsing the
#     old joined key and recovering any legacy epoch value to a calendar day.
#   - Top level: ensures `dismissedIssues` / `trackedRegions` exist, synthesizes
#     `primaryRegions` from the tracked ids (null appearance, listed order) when
#     absent, adds empty device/policy tables, stamps legacy samples with null
#     device provenance, and sets `formatVersion` to 3 (the current version).
#
# Idempotent: re-running on an already-upgraded archive is a no-op (it only
# touches legacy `date` / `key` fields and unmapped region ids).
#
# Usage (from the repo root):
#   ruby Where/Tools/upgrade-backup.rb INPUT.zip [OUTPUT.zip]
#
# OUTPUT defaults to `INPUT-upgraded.zip`. Requires the `zip` / `unzip` CLIs.

require "json"
require "tmpdir"
require "fileutils"
require "time"
require "set"

MANIFEST_NAME = "manifest.json"
CURRENT_FORMAT_VERSION = 3

# Former enum-case region ids -> current catalog ids. `canada` / `other` are
# unchanged but listed so an already-current id passes through untouched.
REGION_MAP = {
  "california" => "us-CA",
  "newYork" => "us-NY",
  "europeanUnion" => "european-union",
  "canada" => "canada",
  "other" => "other",
}.freeze

# The dismissal issue types and the query-item name(s) each carries, matching
# `DataIssueID.storeURL` (`store://issues/<type>?<params>`).
ISSUE_PARAM_NAMES = {
  "missingDays" => %w[start],
  "borderDrift" => %w[day],
  "abruptChange" => %w[earlier later],
}.freeze

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

# The set of valid region ids: the bundled catalog plus the `other` sentinel.
def catalog_region_ids
  manifest = File.expand_path("../RegionKit/Sources/Resources/regions.json", __dir__)
  die "regions.json not found at #{manifest}" unless File.exist?(manifest)
  ids = JSON.parse(File.read(manifest)).map { |entry| entry.fetch("id") }
  (ids + ["other"]).to_set
end

VALID_REGION_IDS = catalog_region_ids

# The `%04d-%02d-%02d` calendar day an instant was meant to name, robust to the
# writer's time zone: legacy day keys were midnight in the writer's zone, so we
# nudge ~12h toward noon before reading UTC components (matches
# `CalendarDay.init(recoveringLegacyStartOfDay:in:)`).
def recovered_day_iso(instant_seconds)
  t = Time.at(instant_seconds + (12 * 60 * 60)).utc
  format("%04d-%02d-%02d", t.year, t.month, t.day)
end

# Normalize one identifying value from a legacy dismissal key or manual-day
# `date` into an ISO `YYYY-MM-DD` string.
def value_to_day_iso(value)
  case value
  when /\A\d{4}-\d{2}-\d{2}\z/ # already an ISO calendar day
    value
  when /\A\d+(?:\.\d+)?\z/ # legacy epoch seconds
    recovered_day_iso(value.to_f)
  else
    # A full ISO-8601 instant (legacy manual-day `date`).
    recovered_day_iso(Time.iso8601(value).to_f)
  end
rescue ArgumentError
  die "could not parse day value: #{value.inspect}"
end

def rekey_region(id, warnings)
  return id if id.nil?

  mapped = REGION_MAP.fetch(id, id)
  warnings << "unknown region id #{id.inspect} (kept as-is)" unless VALID_REGION_IDS.include?(mapped)
  mapped
end

def upgrade_evidence!(manifest, warnings)
  Array(manifest["evidence"]).each do |item|
    item["region"] = rekey_region(item["region"], warnings) if item.key?("region")
  end
end

def upgrade_manual_days!(manifest, warnings)
  Array(manifest["manualDays"]).each do |day|
    if day.key?("regions")
      day["regions"] = day["regions"].map { |id| rekey_region(id, warnings) }
    end
    # Legacy absolute `date` instant -> timezone-independent `day`.
    if !day.key?("day") && day.key?("date")
      iso = value_to_day_iso(day.delete("date"))
      year, month, dom = iso.split("-").map(&:to_i)
      day["day"] = { "year" => year, "month" => month, "day" => dom }
    end
    day["isAuthoritative"] = false unless day.key?("isAuthoritative")
  end
end

# Build a `store://issues/<type>?<params>` URL string with sorted query items,
# matching `StoreURL.url` / `DataIssueID.storeURL`.
def issue_store_url(type, values)
  names = ISSUE_PARAM_NAMES.fetch(type) do
    die "unknown dismissal issue type: #{type.inspect}"
  end
  unless names.length == values.length
    die "dismissal key for #{type.inspect} has #{values.length} value(s), expected #{names.length}"
  end
  query = names.zip(values).sort_by(&:first).map { |name, value| "#{name}=#{value}" }.join("&")
  "store://issues/#{type}?#{query}"
end

def upgrade_dismissals!(manifest)
  Array(manifest["dismissedIssues"]).each do |dismissal|
    next unless dismissal.key?("key") # already `id`-shaped -> leave it

    key = dismissal.delete("key")
    type, *raw_values = key.split(":")
    values = raw_values.map { |value| value_to_day_iso(value) }
    dismissal["id"] = issue_store_url(type, values)
  end
end

def upgrade_manifest(manifest)
  warnings = []
  upgrade_evidence!(manifest, warnings)
  upgrade_manual_days!(manifest, warnings)
  upgrade_dismissals!(manifest)
  if manifest.key?("trackedRegions")
    manifest["trackedRegions"] = manifest["trackedRegions"].map { |id| rekey_region(id, warnings) }
  end
  manifest["dismissedIssues"] ||= []
  manifest["trackedRegions"] ||= []
  # v2 adds `primaryRegions` (each tracked region's picked look + order).
  # A pre-v2 archive has no picked looks, so synthesize entries from the
  # tracked ids with a null appearance, in their listed order.
  manifest["primaryRegions"] ||= manifest["trackedRegions"].each_with_index.map do |id, index|
    { "region" => id, "appearance" => nil, "order" => index }
  end
  Array(manifest["samples"]).each do |sample|
    sample["recordingDeviceID"] = nil unless sample.key?("recordingDeviceID")
  end
  manifest["recordingDevices"] ||= []
  manifest["recordingPolicyChanges"] ||= []
  manifest["formatVersion"] = CURRENT_FORMAT_VERSION
  warnings.uniq.each { |message| warn "warning: #{message}" }
  manifest
end

def run_or_die(*command)
  return if system(*command)

  die "command failed: #{command.join(' ')}"
end

def main(argv)
  if argv.empty? || argv.include?("--help") || argv.include?("-h")
    print_usage
    exit(argv.empty? ? 1 : 0)
  end

  input = argv[0]
  die "input not found: #{input}" unless File.exist?(input)
  output = argv[1] || input.sub(/(\.zip)?\z/i, "-upgraded.zip")
  output = File.expand_path(output)

  Dir.mktmpdir("where-backup-upgrade") do |work|
    run_or_die("unzip", "-q", File.expand_path(input), "-d", work)

    manifest_path = File.join(work, MANIFEST_NAME)
    die "#{MANIFEST_NAME} not found in archive (is this a Where backup?)" unless File.exist?(manifest_path)

    manifest = JSON.parse(File.read(manifest_path))
    upgraded = upgrade_manifest(manifest)
    # Pretty-printed + sorted keys to match the app's exporter.
    File.write(manifest_path, "#{JSON.pretty_generate(sort_deep(upgraded))}\n")

    FileUtils.rm_f(output)
    entries = Dir.children(work)
    Dir.chdir(work) { run_or_die("zip", "-q", "-r", "-X", output, *entries) }
  end

  puts "Wrote #{output}"
end

# Recursively sort hash keys so the manifest is byte-stable like the app's
# `.sortedKeys` encoder output.
def sort_deep(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, out| out[key] = sort_deep(value[key]) }
  when Array
    value.map { |element| sort_deep(element) }
  else
    value
  end
end

main(ARGV)
