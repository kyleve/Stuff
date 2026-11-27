#!/usr/bin/env ruby
# frozen_string_literal: true

# Reshapes legacy Where backups into the current v11 manifest. The automatic-recording feature
# was not shipped in v1 or v2, so upgrading adds empty recording tables without inventing consent.
# v4 expands device kinds and groups metadata edit payloads; v5 adds the planned-stay register.
# v6 preserves optional motion readings and adds per-sample attribution history.
# v7 expands the stay register into independent plans and adds the forecast home-region register.
# v8 admits Canadian subdivisions. v9 requires GPS capture and correction author device IDs.
# v10 adds a stable hardware-model fact for each registered installation.
# v11 records the author of each retained action.

require "json"
require "digest"
require "tmpdir"
require "time"
require "optparse"
require "set"
require "date"

MANIFEST_NAME = "manifest.json"
CURRENT_FORMAT_VERSION = 11
SUPPORTED_SOURCE_FORMAT_VERSIONS = (1..CURRENT_FORMAT_VERSION).freeze
# All legacy singular records revised the same logical stay. Keep that identity across archives, including
# clearing tombstones, so merging upgraded backups cannot revive superseded plans.
LEGACY_PLANNED_STAY_ID = "9D6B2F5A-2C8E-4B91-9D43-E7F41A0916C0"

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
  lastSeenAt auditRecordedAt auditLocationTimestamp updatedAt
].to_set.freeze

def die(message)
  warn "error: #{message}"
  exit 1
end

def catalog_region_ids
  path = File.expand_path("../RegionKit/Sources/Resources/regions.json", __dir__)
  die "regions.json not found at #{path}" unless File.exist?(path)
  (JSON.parse(File.read(path)).filter_map { |entry| entry.fetch("id") if entry.fetch("isLoggable") } + ["other"]).to_set
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
    profile["kind"] = { kind => {} } if kind.is_a?(String)
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

def upgrade_planned_stays!(manifest, source_version)
  return unless source_version < 7

  Array(manifest["plannedStayRecords"]).each do |record|
    # The itinerary prototype used v6 before main added motion. Preserve its independent IDs.
    next if record.key?("stayID")

    record["stayID"] = LEGACY_PLANNED_STAY_ID
    value = record["value"]
    next if value.nil?

    through = value.fetch("through")
    departure = Date.new(through.fetch("year"), through.fetch("month"), through.fetch("day"), Date::GREGORIAN)
    # v5 and main's v6 never stored arrival. The revision's UTC day is a stable inference across exports;
    # exportedAt would give one revision conflicting payloads in backups made on different days.
    # Clamp future clock skew and already-completed plans so arrival cannot follow departure.
    updated_at = record.fetch("updatedAt")
    die "planned-stay updatedAt must be a timestamp" unless updated_at.is_a?(Numeric) && updated_at.finite?
    updated_time = Time.at(updated_at).utc
    updated_day = Date.new(updated_time.year, updated_time.month, updated_time.day, Date::GREGORIAN)
    arrival = [updated_day, departure].min
    arrival_day = { "year" => arrival.year, "month" => arrival.month, "day" => arrival.day }
    record["value"] = {
      "id" => LEGACY_PLANNED_STAY_ID,
      "region" => value.fetch("region"),
      "arrival" => { "earliest" => arrival_day.dup, "latest" => arrival_day.dup },
      "departure" => { "earliest" => through.dup, "latest" => through.dup },
    }
  rescue KeyError, ArgumentError, RangeError => error
    die "could not upgrade planned stay: #{error.message}"
  end
end

UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
MANIFEST_COLLECTIONS = %w[
  samples evidence manualDays dismissedIssues trackedRegions primaryRegions recordingDeviceProfiles
  recordingDeviceMetadataChanges recordingDeviceRemovals plannedStayRecords homeRegionRecords
  sampleAttributionRevisions assets
].freeze

def device_id(value)
  die "expected a store://devices/<uuid> device ID" unless value.is_a?(String) && value.match?(%r{\Astore://devices/#{UUID_PATTERN}\z})
  value.downcase
end

def record_uuid(value)
  die "expected a UUID record identity" unless value.is_a?(String) && value.match?(/\A#{UUID_PATTERN}\z/)
  value.downcase
end

# Compare the persisted identity of the observation, independent of coordinates, motion,
# and the display label attached to EvidenceKind.other. This matches LocationSample.hasSameOrigin.
def sample_origin(sample)
  source, value = sample.fetch("source").first
  device = sample["recordingDeviceID"]
  origin = [source, device && device_id(device)]
  if source == "evidenceImplied"
    origin << record_uuid(value.fetch("id")) << value.fetch("kind").keys.first
  end
  origin
end

def validate_duplicate_samples!(samples)
  first = {}
  samples.each do |sample|
    id = record_uuid(sample["id"])
    if first.key?(id)
      die "conflicting source for the same sample ID" if sample_origin(first[id]) != sample_origin(sample)
    else
      first[id] = sample
    end
  end
end

def validate_revisions!(revisions)
  values = {}
  revisions.each do |revision|
    id = record_uuid(revision["id"])
    timestamp = revision["updatedAt"]
    regions = revision["replacementRegions"]
    unless timestamp.is_a?(Numeric) && timestamp.finite? &&
           (regions.nil? || (regions.is_a?(Array) && regions.all?(String)))
      die "invalid sample-attribution revision payload"
    end
    # Swift compares a Set<Region>? here: null (restore), [] (exclude) and a set of
    # replacements have different meanings; order and repeated region IDs do not.
    value = [record_uuid(revision["sampleID"]), timestamp, device_id(revision["changedByDeviceID"]), regions&.uniq&.sort]
    die "conflicting immutable revisions for the same ID" if values.key?(id) && values[id] != value
    values[id] = value
  end
end

# A stay or home revision's UUID permanently identifies both its author and
# its value. Multiple revisions of the same logical stay keep distinct UUIDs.
def validate_planning_duplicates!(manifest)
  %w[plannedStayRecords homeRegionRecords].each do |table|
    manifest.fetch(table).group_by { |row| record_uuid(row.fetch("id")) }.each_value do |duplicates|
      next if duplicates.one?
      values = duplicates.map do |row|
        identity = [device_id(row.fetch("changedByDeviceID")), row.fetch("updatedAt")]
        if table == "homeRegionRecords"
          identity << row["region"]
        else
          value = row["value"]
          identity << record_uuid(row.fetch("stayID"))
          identity << (value && [record_uuid(value.fetch("id")), value.fetch("region"), value.fetch("arrival"), value.fetch("departure")])
        end
        identity
      end
      die "conflicting immutable #{table} revisions for the same ID" unless values.uniq.one?
    end
  end
end

def profile_identity(profile)
  die "expected an immutable recording-device profile" unless profile.is_a?(Hash)
  id = device_id(profile["id"])
  generation = profile.dig("registrationGenerationID", "rawValue") if profile["registrationGenerationID"].is_a?(Hash)
  kind = profile["kind"]
  unless profile["systemName"].is_a?(String) &&
         profile["registeredAt"].is_a?(Numeric) && profile["registeredAt"].finite? &&
         generation.is_a?(String) && generation.match?(/\A#{UUID_PATTERN}\z/) &&
         kind.is_a?(Hash) && kind.size == 1 && %w[phone tablet computer watch other].include?(kind.keys.first) &&
         kind.values.first.is_a?(Hash)
    die "source profile requires systemName, kind, registeredAt and registrationGenerationID.rawValue"
  end
  [id, profile["systemName"], kind, profile["registeredAt"], generation.downcase]
end

def index_profiles(records)
  profiles = {}
  records.each do |profile|
    identity = profile_identity(profile)
    id = identity.first
    die "conflicting immutable profiles for the same device ID" if profiles.key?(id) && profiles[id] != identity
    profiles[id] = identity
  end
  profiles
end

# Validate the supplied mapping even when every stored origin already exists.
def selected_device(source_profile, profiles, known)
  die "source profile must be a JSON object" unless source_profile.is_a?(Hash)
  id = device_id(source_profile["id"])
  if source_profile.keys == ["id"]
    die "selected source ID is absent from the archive. Provide its full profile" unless known.include?(id)
  else
    identity = profile_identity(source_profile)
    die "source profile conflicts with immutable archive profile" if profiles.key?(id) && profiles[id] != identity
    unless source_profile.keys.sort == %w[id kind registeredAt registrationGenerationID systemName] &&
           (profiles.key?(id) || !source_profile.fetch("systemName").strip.empty?)
      die "provide the original immutable profile fields and a nonempty systemName for a new profile"
    end
  end
  id
end

# A group identifies one immutable role. An evidence item and all observations
# derived from it share its adding device. Mutable day, dismissal and region
# snapshots can represent different edits of the same natural key.
def each_device_role(manifest)
  manifest.fetch("samples").each do |sample|
    id = record_uuid(sample["id"])
    source = sample.fetch("source")
    die "invalid sample source" unless source.is_a?(Hash) && source.size == 1
    kind, payload = source.first
    case kind
    when "gpsVisit", "gpsSignificantChange"
      die "GPS sample contains an assertion author" unless sample["assertedByDeviceID"].nil?
      yield sample, "recordingDeviceID", 9, [:capture, id]
    when "manual", "evidenceImplied"
      # A historical capture tag on a non-GPS sample is preserved as a separate field.
      capture = sample["recordingDeviceID"]
      yield sample, "recordingDeviceID", 9, [:capture, id] unless capture.nil?
      if kind == "manual"
        yield sample, "assertedByDeviceID", 11, [:assertion, id], capture
      else
        yield sample, "assertedByDeviceID", 11, [:evidence, record_uuid(payload.fetch("id"))]
      end
    else die "unknown sample source"
    end
  end
  manifest.fetch("sampleAttributionRevisions").each do |row|
    yield row, "changedByDeviceID", 9, [:correction, record_uuid(row["id"])]
  end
  manifest.fetch("evidence").each do |row|
    yield row, "addedByDeviceID", 11, [:evidence, record_uuid(row["id"])]
  end
  %w[plannedStayRecords homeRegionRecords].each do |table|
    manifest.fetch(table).each do |row|
      yield row, "changedByDeviceID", 11, [table, record_uuid(row["id"])]
    end
  end
  { "manualDays" => "changedByDeviceID", "dismissedIssues" => "dismissedByDeviceID",
    "primaryRegions" => "changedByDeviceID" }.each do |table, key|
    manifest.fetch(table).each_with_index { |row, index| yield row, key, 11, [table, index] }
  end
end

def upgrade_device_roles!(manifest, source_version, source_profile)
  profiles = index_profiles(manifest.fetch("recordingDeviceProfiles"))
  known = profiles.keys.to_set
  manifest.fetch("recordingDeviceMetadataChanges").each do |change|
    known << device_id(change.fetch("deviceID")) << device_id(change.fetch("changedByDeviceID"))
  end
  manifest.fetch("recordingDeviceRemovals").each do |removal|
    known << device_id(removal.fetch("deviceID")) << device_id(removal.fetch("removedByDeviceID"))
  end

  missing = []
  origins = {}
  each_device_role(manifest) do |row, key, required_since, group, prior_capture|
    if row[key].nil?
      die "v#{source_version} archive is missing #{key}" if source_version >= required_since
      missing << [row, key, group, prior_capture]
    else
      id = device_id(row[key])
      die "conflicting authors or origins for #{group.first}" if origins.key?(group) && origins[group] != id
      origins[group] = id
      known << id
    end
  end

  selected = selected_device(source_profile, profiles, known) if source_profile
  selected ||= known.first if known.one?
  used_selected = false
  missing.each do |row, key, group, prior_capture|
    origin = origins[group] || (prior_capture && device_id(prior_capture)) || selected
    die "cannot identify the original installation unambiguously. Pass --source-profile FILE" unless origin
    row[key] = origin
    used_selected ||= origin == selected
  end
  return unless used_selected && source_profile && source_profile.keys != ["id"] && !profiles.key?(selected)

  manifest.fetch("recordingDeviceProfiles") << source_profile
  selected
end

HARDWARE_MODEL_FIELD = "hardwareModelIdentifier"
HARDWARE_MODEL_NAMESPACE = "com.stuff.where.device-hardware-model.v1"

# UUIDv8 shared with RecordingDeviceMetadataChange.hardwareModelEventID(for:).
def hardware_model_event_id(installation_uuid)
  digest = Digest::SHA256.digest(HARDWARE_MODEL_NAMESPACE + installation_uuid).bytes.first(16)
  digest[6] = (digest[6] & 0x0f) | 0x80
  digest[8] = (digest[8] & 0x3f) | 0x80
  digest.pack("C*").unpack("H8H4H4H4H12").join("-").upcase
end

def hardware_model_identifier(value)
  # Foundation's whitespacesAndNewlines also includes U+200B ZERO WIDTH SPACE.
  die "hardware model identifier must be a nonblank string" unless value.is_a?(String) && value.match?(/[^[:space:]\u200b]/)
  value
end

def device_model_map(mapping)
  die "device model map must be an object keyed by installation UUID" unless mapping.is_a?(Hash)
  mapping.each_with_object({}) do |(id, model), result|
    uuid = record_uuid(id)
    identifier = hardware_model_identifier(model)
    die "conflicting model identifiers for the same installation UUID" if result.key?(uuid) && result[uuid] != identifier
    result[uuid] = identifier
  end
end

def upgrade_hardware_models!(manifest, source_version, mapping, added_profile_id)
  models = device_model_map(mapping)
  metadata = manifest.fetch("recordingDeviceMetadataChanges")
  profiles = manifest.fetch("recordingDeviceProfiles").to_h { |profile| [device_id(profile.fetch("id")), profile] }
  facts = {}
  nickname_ids = Set.new
  metadata.each do |event|
    event_id = record_uuid(event.fetch("id")).upcase
    target = device_id(event.fetch("deviceID"))
    uuid = target.delete_prefix("store://devices/")
    revision = event.fetch("revision")
    date = event.fetch("changedAt")
    payload = event.fetch("payload")
    die "invalid device metadata revision or timestamp" unless revision.is_a?(Integer) && revision.between?(0, (2**63) - 1) && date.is_a?(Numeric) && date.finite?
    case payload.fetch("field")
    when "nickname"
      die "nickname also contains a hardware model" unless payload[HARDWARE_MODEL_FIELD].nil?
      die "invalid nickname value" unless payload["nickname"].nil? || payload["nickname"].is_a?(String)
      nickname_ids << event_id
    when HARDWARE_MODEL_FIELD
      die "hardware model also contains a nickname" unless payload["nickname"].nil?
      identifier = hardware_model_identifier(payload[HARDWARE_MODEL_FIELD])
      unless event_id == hardware_model_event_id(uuid) && revision.zero? && device_id(event.fetch("changedByDeviceID")) == target
        die "invalid hardware model event ID, revision or author"
      end
      die "hardware fact registration time disagrees with profile" if profiles.key?(target) && date != profiles.fetch(target).fetch("registeredAt")
      die "hardware model mapping disagrees with existing fact" if models.key?(uuid) && models.fetch(uuid) != identifier
      fact = [identifier, date]
      die "conflicting hardware model facts for one installation" if facts.key?(target) && facts[target] != fact
      facts[target] = fact
    else
      die "unknown device metadata field"
    end
  end

  # Keep a valid fact delivered before its profile. A complete profile, even one since
  # removed, must acquire exactly one model identity before a legacy archive can become v10.
  (profiles.keys | facts.keys).sort.each do |target|
    uuid = target.delete_prefix("store://devices/")
    id = hardware_model_event_id(uuid)
    die "a nickname uses the reserved hardware model event ID" if nickname_ids.include?(id)
    next if facts.key?(target)
    die "v#{source_version} archive profile is missing its hardware model fact" if source_version >= 10 && target != added_profile_id
    model = models[uuid]
    die "missing original hardware identifier for #{uuid}. Pass --device-models FILE" unless model
    metadata << {
      "id" => id, "deviceID" => target, "revision" => 0,
      "changedAt" => profiles.fetch(target).fetch("registeredAt"), "changedByDeviceID" => target,
      "payload" => { "field" => HARDWARE_MODEL_FIELD, HARDWARE_MODEL_FIELD => model },
    }
  end
end

def upgrade_manifest(manifest, source_profile: nil, device_models: {})
  source_version = source_format_version(manifest)
  manifest = manifest.except("recordingDevices", "recordingDeviceCheckIns", "recordingPolicyChanges")
  # Released v7 and v8 already have the current region, day, date and planning shapes.
  # Older prototypes reused v7 without the forecast Home register.
  if source_version < 7 || (source_version == 7 && !manifest.key?("homeRegionRecords"))
    normalize_legacy_manifest!(manifest, source_version)
  end
  MANIFEST_COLLECTIONS.each do |key|
    die "manifest is missing array #{key}" unless manifest[key].is_a?(Array)
  end
  added_profile_id = upgrade_device_roles!(manifest, source_version, source_profile)
  validate_duplicate_samples!(manifest.fetch("samples"))
  validate_revisions!(manifest.fetch("sampleAttributionRevisions"))
  validate_planning_duplicates!(manifest)
  upgrade_hardware_models!(manifest, source_version, device_models, added_profile_id)
  manifest.merge("formatVersion" => CURRENT_FORMAT_VERSION)
end

def normalize_legacy_manifest!(manifest, source_version)
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
    sample["motion"] = nil unless sample.key?("motion")
  end

  manifest["recordingDeviceProfiles"] ||= []
  manifest["recordingDeviceMetadataChanges"] ||= []
  manifest["recordingDeviceRemovals"] ||= []
  manifest["plannedStayRecords"] ||= []
  manifest["homeRegionRecords"] ||= []
  manifest["sampleAttributionRevisions"] ||= []
  upgrade_recording_devices!(manifest, source_version)
  upgrade_planned_stays!(manifest, source_version)
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
  profile_path = nil
  model_map_path = nil
  parser = OptionParser.new do |options|
    options.banner = "Usage: ruby Where/Tools/upgrade-backup.rb INPUT.zip [OUTPUT.zip] [--source-profile FILE] [--device-models FILE]"
    options.on("--source-profile FILE", "Original installation profile or selection JSON") { |path| profile_path = path }
    options.on("--device-models FILE", "JSON object mapping installation UUIDs to raw hardware model identifiers") { |path| model_map_path = path }
    options.on("-h", "--help", "Show usage") { puts options; return }
  end
  arguments = parser.parse(argv)
  die parser.to_s unless (1..2).cover?(arguments.size)
  input = File.expand_path(arguments.first)
  die "input not found: #{input}" unless File.file?(input)
  output = File.expand_path(arguments[1] || input.sub(/(\.zip)?\z/i, "-upgraded.zip"))
  die "input and output refer to the same file" if File.identical?(input, output)
  if profile_path
    source_profile = JSON.parse(File.read(profile_path))
    die "source profile must be a JSON object" unless source_profile.is_a?(Hash)
    die "output would overwrite the source profile" if File.identical?(profile_path, output)
  end

  models = {}
  if model_map_path
    die "output would overwrite the device model map" if File.identical?(model_map_path, output)
    models = JSON.parse(File.read(model_map_path))
  end

  Dir.mktmpdir("where-backup-upgrade") do |work|
    run_or_die("unzip", "-q", File.expand_path(input), "-d", work)
    manifest_path = File.join(work, MANIFEST_NAME)
    die "#{MANIFEST_NAME} not found in archive (is this a Where backup?)" unless File.exist?(manifest_path)

    manifest = JSON.parse(File.read(manifest_path))
    upgraded = upgrade_manifest(manifest, source_profile: source_profile, device_models: models)
    File.write(manifest_path, JSON.pretty_generate(sort_deep(upgraded)) + "\n")
    Dir.mktmpdir(".where-backup-output-", File.dirname(output)) do |staging|
      zipped = File.join(staging, "backup.zip")
      Dir.chdir(work) { run_or_die("zip", "-q", "-r", zipped, ".") }
      File.rename(zipped, output)
    end
  end
  puts output
rescue OptionParser::ParseError, JSON::ParserError, SystemCallError, KeyError, TypeError => error
  die error.message
end

main(ARGV) if $PROGRAM_NAME == __FILE__
