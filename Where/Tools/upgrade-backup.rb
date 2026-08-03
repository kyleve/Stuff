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
#   - Recording devices: splits the v3 aggregate rows into immutable profiles,
#     append-only nickname metadata, target-owned check-ins, and causally ordered
#     complete-authority policy events. Interim archive metadata is folded into
#     that policy stream, boolean policy values become explicit state/reason,
#     and pre-v6 flat revisions are parent-linked into a deterministic causal
#     branch while retaining concurrent losing events for audit/cleanup; v6's
#     scalar `parentID` becomes v7's sorted `parentIDs` set so current commands
#     can causally join every observed concurrent head.
#     v1-v4 profiles are stamped as registrations from the initial logical data
#     epoch; v4's nickname/check-in rows remain untouched and its flat policy
#     revisions gain parent links without being reordered or renumbered.
#   - Top level: ensures `dismissedIssues` / `trackedRegions` exist, synthesizes
#     `primaryRegions` from the tracked ids (null appearance, listed order) when
#     absent, adds empty device/policy tables, stamps legacy samples with null
#     device provenance, and sets `formatVersion` to 7 (the current version).
#
# Idempotent: re-running on an already-upgraded archive is a no-op; every legacy
# date, id, and recording-authority transform converges on one stable value.
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
require "digest"

MANIFEST_NAME = "manifest.json"
CURRENT_FORMAT_VERSION = 8
INITIAL_DATA_EPOCH_ID = "00000000-0000-0000-0000-0000000000E0"
SUPPORTED_SOURCE_FORMAT_VERSIONS = (1..CURRENT_FORMAT_VERSION).freeze

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

def deterministic_uuid(seed)
  hex = Digest::SHA256.hexdigest(seed)[0, 32]
  hex[12] = "5"
  hex[16] = ((hex[16].to_i(16) & 0x3) | 0x8).to_s(16)
  [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
end

def instant_seconds(value)
  value.is_a?(Numeric) ? value.to_f : Time.iso8601(value).to_f
rescue ArgumentError
  0.0
end

def policy_sort_key(change)
  [instant_seconds(change.fetch("effectiveAt")), change.fetch("id")]
end

def normalize_policy!(change)
  change["issuedAt"] ||= change.fetch("effectiveAt")
  # The v3 wire format did not retain the author. The target installation is
  # the only deterministic attribution available during an out-of-band upgrade.
  change["issuedByDeviceID"] ||= change.fetch("deviceID")

  unless change.key?("state")
    enabled = change.delete("isEnabled") do
      die "recording policy #{change.fetch('id').inspect} has neither state nor isEnabled"
    end
    change["state"] = enabled ? "on" : "off"
  end
  change.delete("isEnabled")
  change["reason"] ||= if change.fetch("state") == "archived"
    "archive"
  elsif change.fetch("revision", 0).zero? && change.fetch("issuedByDeviceID") == change.fetch("deviceID")
    "initialRegistration"
  else
    "userCommand"
  end
end

def policy_conflict_key(change)
  reason_priority = case change.fetch("reason")
  when "backupReplace" then 1
  when "accountReset" then 2
  else 0
  end
  state_priority = case change.fetch("state")
  when "on" then 0
  when "off" then 1
  when "archived" then 2
  else die "unknown recording policy state #{change.fetch('state').inspect}"
  end
  [reason_priority, state_priority, change.fetch("id")]
end

# Pre-v6 archives had only flat revisions, so the actual parent of a command written after a
# concurrent fork is unknowable. Link every event at the next revision to the same deterministic
# winner the old reader treated as current. This preserves the old archive's resolved authority;
# future writes will carry their exact observed parent and cannot cross branches.
def upgrade_policy_parents!(manifest, source_version)
  return if source_version >= 6

  Array(manifest["recordingPolicyChanges"])
    .group_by { |change| change.fetch("deviceID") }
    .each_value do |changes|
      by_revision = changes.group_by { |change| change.fetch("revision") }
      revisions = by_revision.keys.sort
      unless revisions.first == 0 && revisions.each_cons(2).all? { |before, after| after == before + 1 }
        die "recording policy revisions must begin at zero without gaps"
      end

      parent = nil
      revisions.each do |revision|
        siblings = by_revision.fetch(revision)
        siblings.each do |change|
          if revision.zero?
            change.delete("parentID")
          else
            change["parentID"] = parent.fetch("id")
          end
        end
        parent = siblings.max_by { |change| policy_conflict_key(change) }
      end
    end
end

# v6 could name only one causal parent. The v7 wire shape always carries the full sorted parent
# frontier; legacy events can only contribute an empty root set or one already-canonical parent.
def upgrade_policy_parent_sets!(manifest, source_version)
  return if source_version >= 7

  Array(manifest["recordingPolicyChanges"]).each do |change|
    parent_id = change.delete("parentID")
    change["parentIDs"] = parent_id.nil? ? [] : [parent_id]
  end
end

def archive_policy_change(metadata)
  metadata_id = metadata.fetch("id")
  {
    "id" => deterministic_uuid(
      ["recording-policy-from-archive-metadata", metadata_id].join(":"),
    ),
    "deviceID" => metadata.fetch("deviceID"),
    "issuedAt" => metadata.fetch("changedAt"),
    "issuedByDeviceID" => metadata.fetch("changedByDeviceID"),
    "effectiveAt" => metadata.fetch("changedAt"),
    "archiveValue" => metadata.fetch("isArchived"),
  }
end

def upgrade_pre_v4_recording_devices!(manifest)
  legacy_devices = Array(manifest.delete("recordingDevices"))

  manifest["recordingDeviceProfiles"] ||= legacy_devices.map do |device|
    {
      "id" => device.fetch("id"),
      "systemName" => device.fetch("systemName"),
      "kind" => device.fetch("kind"),
      "registeredAt" => device.fetch("registeredAt"),
    }
  end

  manifest["recordingDeviceMetadataChanges"] ||= legacy_devices.filter_map do |device|
    device_id = device.fetch("id")
    next if device["nickname"].nil?

    changed_at = device["lastSeenAt"] || device.fetch("registeredAt")
    nickname = device.fetch("nickname")
    seed = ["recording-device-metadata", device_id, "nickname", nickname, changed_at]
      .map(&:to_json).join(":")
    {
      "id" => deterministic_uuid(seed),
      "deviceID" => device_id,
      "field" => "nickname",
      "revision" => 0,
      "changedAt" => changed_at,
      "changedByDeviceID" => device_id,
      "nickname" => nickname,
    }
  end

  manifest["recordingDeviceCheckIns"] ||= legacy_devices.filter_map do |device|
    policy_id = device["lastAppliedPolicyChangeID"]
    status = device.fetch("status")
    next if policy_id.nil? || status == "unknown"

    last_seen_at = device["lastSeenAt"] || device.fetch("registeredAt")
    {
      "deviceID" => device.fetch("id"),
      "revision" => 0,
      "lastSeenAt" => last_seen_at,
      "appliedAt" => last_seen_at,
      "lastAppliedPolicyChangeID" => policy_id,
      "status" => status,
    }
  end

  policies = Array(manifest["recordingPolicyChanges"])
  policies.group_by { |change| change.fetch("deviceID") }.each_value do |changes|
    changes.sort_by { |change| policy_sort_key(change) }.each_with_index do |change, revision|
      change["revision"] ||= revision
      normalize_policy!(change)
    end
  end

  metadata = Array(manifest["recordingDeviceMetadataChanges"])
  archive_metadata, nickname_metadata = metadata.partition { |change| change["field"] == "archive" }
  manifest["recordingDeviceMetadataChanges"] = nickname_metadata

  legacy_archive_metadata = legacy_devices.filter_map do |device|
    next if device["archivedAt"].nil?

    changed_at = device.fetch("archivedAt")
    seed = ["recording-device-metadata", device.fetch("id"), "archive", true, changed_at]
      .map(&:to_json).join(":")
    {
      "id" => deterministic_uuid(seed),
      "deviceID" => device.fetch("id"),
      "changedAt" => changed_at,
      "changedByDeviceID" => device.fetch("id"),
      "isArchived" => true,
    }
  end

  archive_commands = archive_metadata.map { |change| archive_policy_change(change) }
  # `recordingDevices.archivedAt` is the v3 aggregate's final state, not merely another event
  # ordered by wall clock. The paired Off cutoff can legitimately be later than `archivedAt`
  # because the old writer forced effective timestamps to increase monotonically. Preserve the
  # aggregate's final archived state by ordering this synthesized authority after every ordinary
  # policy event for the device.
  final_archive_commands = legacy_archive_metadata.map do |change|
    archive_policy_change(change)
  end

  # The old archive-event and desired-policy streams had no shared causal revision. Merge those
  # events by effective instant, placing archive commands after ordinary policy commands at the
  # same instant. The aggregate's final `archivedAt` marker is the exception handled above: it
  # must remain final regardless of its paired Off cutoff. An unarchive resumes the most recent
  # non-archive desired state instead of silently enabling recording.
  merged = (policies.map { |change| [change, false, false] } +
    archive_commands.map { |change| [change, true, false] } +
    final_archive_commands.map { |change| [change, true, true] })
    .group_by { |change, _archive, _final_archive| change.fetch("deviceID") }
    .flat_map do |_device_id, entries|
      last_non_archive_state = "off"
      entries.sort_by do |change, archive, final_archive|
        [
          final_archive ? 1 : 0,
          instant_seconds(change.fetch("effectiveAt")),
          archive ? 1 : 0,
          change.fetch("id"),
        ]
      end.each_with_index.map do |(change, archive, _final_archive), revision|
        if archive
          archived = change.delete("archiveValue")
          change["state"] = archived ? "archived" : last_non_archive_state
          change["reason"] = archived ? "archive" : "userCommand"
        elsif change.fetch("state") != "archived"
          last_non_archive_state = change.fetch("state")
        end
        change["revision"] = revision
        change
      end
    end
  manifest["recordingPolicyChanges"] = merged
end

def upgrade_recording_devices!(manifest, source_version)
  if source_version < 4
    upgrade_pre_v4_recording_devices!(manifest)
  else
    # v4 already has independent causal tables. In particular, do not sort or
    # renumber its policy events by wall clock: offline writers can legitimately
    # produce multiple events at one revision, and their revision is authority.
    manifest.delete("recordingDevices")
    manifest["recordingDeviceProfiles"] ||= []
    manifest["recordingDeviceMetadataChanges"] ||= []
    manifest["recordingDeviceCheckIns"] ||= []
    manifest["recordingPolicyChanges"] ||= []
  end

  Array(manifest["recordingDeviceProfiles"]).each do |profile|
    profile["registrationEpochID"] ||= { "rawValue" => INITIAL_DATA_EPOCH_ID }
  end
  upgrade_policy_parents!(manifest, source_version)
  upgrade_policy_parent_sets!(manifest, source_version)
end

def source_format_version(manifest)
  version = manifest["formatVersion"]
  unless version.is_a?(Integer)
    die "manifest formatVersion must be an integer"
  end
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
  manifest["recordingPolicyChanges"] ||= []
  manifest["recordingAssignmentChanges"] ||= []
  manifest["recordingDeviceArchives"] ||= []
  upgrade_recording_devices!(manifest, source_version)
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

main(ARGV) if $PROGRAM_NAME == __FILE__
