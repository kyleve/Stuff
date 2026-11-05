# frozen_string_literal: true

require "time"
require "date"

# Explicit, reusable historical mappings. This converter never borrows the importing phone's
# identity or current zone. Already attributed observations and calendar assignments are immutable.
module RecordingBackupConversion
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  GPS_SOURCES = %w[gpsVisit gpsSignificantChange].freeze
  MAX_OFFSET_SECONDS = 18 * 60 * 60

  def self.apply(manifest, mapping:)
    raise ArgumentError, "recording conversion requires backup format 8" unless manifest["formatVersion"] == 8
    unless [0, 1].include?(manifest["requiredDataMajor"])
      raise ArgumentError, "unsupported data major; conversion cannot lower the compatibility floor"
    end
    raise ArgumentError, "recording map must contain a samples object" unless mapping.is_a?(Hash) && mapping["samples"].is_a?(Hash)

    manifest.fetch("samples").each do |sample|
      next unless sample["source"].is_a?(Hash) && GPS_SOURCES.any? { |source| sample["source"].key?(source) }

      sample_id = sample.fetch("id")
      raise ArgumentError, "invalid sample UUID #{sample_id.inspect}" unless sample_id.is_a?(String) && UUID_PATTERN.match?(sample_id)
      mapped = mapping.fetch("samples")[sample_id] || mapping.fetch("samples")[sample_id.upcase] || {}
      raise ArgumentError, "invalid mapping for sample #{sample_id}" unless mapped.is_a?(Hash)

      existing_device = sample["recordingDeviceID"]
      existing_uuid = device_uuid(existing_device) if existing_device
      mapped_uuid = device_uuid(mapped["recordingDeviceID"]) if mapped["recordingDeviceID"]
      if existing_uuid && mapped_uuid && existing_uuid != mapped_uuid
        raise ArgumentError, "mapping changes the recorded device for sample #{sample_id}"
      end
      device = existing_uuid || mapped_uuid
      raise ArgumentError, "missing or invalid recording device for sample #{sample_id}" unless device

      timestamp = sample.fetch("timestamp")
      raise ArgumentError, "invalid recording timestamp" unless timestamp.is_a?(Numeric) && timestamp.finite?
      # Use the reference-date Double that Foundation will decode. Converting an old Unix
      # timestamp can round across midnight; assigning its day before conversion would disagree.
      # Rational addition then avoids introducing another rounding step for calendar work.
      observation_time = timestamp.to_f.to_r + 978_307_200
      mapped_day = day_from_mapping(mapped.fetch("calendar"), observation_time) if mapped.key?("calendar")
      existing_day = sample["recordingDay"]
      if existing_day && mapped_day && canonical_assignment(existing_day) != mapped_day
        raise ArgumentError, "mapping changes the recording day for sample #{sample_id}"
      end
      assignment = existing_day || mapped_day
      raise ArgumentError, "missing calendar mapping for sample #{sample_id}; explicitly mark unknown context unresolved" unless assignment
      validate_assignment(assignment, observation_time)
      sample["recordingDeviceID"] = existing_device&.start_with?("store://") ? existing_device : "store://devices/#{device}"
      sample["recordingDay"] = assignment
    end
    manifest["requiredDataMajor"] = 1
    manifest
  end

  def self.device_uuid(value)
    raise ArgumentError, "invalid recording device" unless value.is_a?(String)
    uuid = value.start_with?("store://devices/") ? value.delete_prefix("store://devices/") : value
    raise ArgumentError, "invalid recording device" unless UUID_PATTERN.match?(uuid)
    uuid.downcase
  end

  def self.day_from_mapping(calendar, timestamp)
    raise ArgumentError, "calendar mapping must be an object" unless calendar.is_a?(Hash)
    return { "unresolved" => {} } if calendar == { "unresolved" => true }
    unless calendar.keys.sort == %w[secondsFromGMT timeZone]
      raise ArgumentError, "calendar mapping needs timeZone and secondsFromGMT, or unresolved: true"
    end
    context = context_at(timestamp, calendar.fetch("timeZone"), calendar.fetch("secondsFromGMT"))
    { "resolved" => { "_0" => context } }
  end

  def self.validate_assignment(assignment, timestamp)
    return if assignment == { "unresolved" => {} }
    unless assignment.is_a?(Hash) && assignment.keys == ["resolved"] && assignment["resolved"].is_a?(Hash)
      raise ArgumentError, "invalid recording day assignment"
    end
    context = assignment.fetch("resolved").fetch("_0")
    expected = context_at(timestamp, context.fetch("timeZone").fetch("identifier"), context.fetch("secondsFromGMT"))
    raise ArgumentError, "recording day does not match the timestamp and saved UTC offset" unless canonical_assignment(assignment).fetch("resolved").fetch("_0") == expected
  rescue KeyError, TypeError
    raise ArgumentError, "invalid recording day assignment"
  end

  def self.canonical_zone(zone)
    ["UTC", "GMT+0000", "GMT-0000"].include?(zone) ? "GMT" : zone
  end

  def self.canonical_assignment(assignment)
    copy = Marshal.load(Marshal.dump(assignment))
    if copy.is_a?(Hash) && (zone = copy.dig("resolved", "_0", "timeZone")).is_a?(Hash)
      zone["identifier"] = canonical_zone(zone["identifier"])
    end
    copy
  end

  def self.valid_zone_identifier?(zone)
    return false unless zone.is_a?(String)
    if (fixed = /\AGMT[+-](\d{2})(\d{2})\z/.match(zone))
      hours, minutes = fixed.captures.map(&:to_i)
      return minutes < 60 && hours * 3600 + minutes * 60 <= MAX_OFFSET_SECONDS
    end
    /\A[A-Za-z0-9_+\/-]+\z/.match?(zone) && !zone.start_with?("/") &&
      (zone == "GMT" || zone == "UTC" || File.file?(File.join("/usr/share/zoneinfo", zone)))
  end

  def self.context_at(timestamp, zone, offset)
    unless timestamp.is_a?(Numeric) && timestamp.finite? && offset.is_a?(Integer) && offset.abs <= MAX_OFFSET_SECONDS
      raise ArgumentError, "invalid recording timestamp or UTC offset"
    end
    # Zone names describe supplied historical context; the supplied offset determines the date.
    # Do not consult today's tzdb to recalculate that historical offset.
    unless valid_zone_identifier?(zone)
      raise ArgumentError, "unknown time-zone identifier #{zone.inspect}"
    end
    instant = Time.at(timestamp).getlocal(offset)
    # Foundation's Gregorian Calendar uses the 1582 cutover. Ruby Time uses a proleptic
    # Gregorian date. Match the production decoder for historical timestamps as well.
    absolute_day = Date.new(instant.year, instant.month, instant.day, Date::GREGORIAN).jd
    day = Date.jd(absolute_day, Date::ITALY)
    raise ArgumentError, "recording year must be in 1..9999" unless (1..9999).cover?(day.year)
    {
      "day" => { "year" => day.year, "month" => day.month, "day" => day.day },
      "timeZone" => { "identifier" => canonical_zone(zone) },
      "secondsFromGMT" => offset,
    }
  end
end
