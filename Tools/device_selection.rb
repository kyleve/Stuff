# frozen_string_literal: true

require "json"
require "optparse"

# Selects one exact physical iOS device from devicectl's JSON output.
class DeviceSelection
  class Error < StandardError; end

  Selection = Struct.new(:identifier, :name, :connection, keyword_init: true)

  def self.select(json:, filter:)
    data = JSON.parse(json)
    devices = data.dig("result", "devices")
    raise Error, "devicectl's result has no devices array" unless devices.is_a?(Array)

    wanted = filter.strip.downcase
    candidates = devices.filter_map do |device|
      next unless device.is_a?(Hash)

      properties = device["properties"]
      next unless properties.is_a?(Hash)

      hardware = properties["hardware"] || {}
      connection = properties["connection"] || {}
      state = properties["state"] || {}
      next unless %w[ios ipados].include?(hardware.fetch("platform", "").to_s.downcase)
      next unless hardware.fetch("reality", "").to_s.downcase == "physical"

      identifier = device["identifier"] || hardware["udid"]
      next unless identifier.is_a?(String) && !identifier.empty?

      name = state["name"].is_a?(String) && !state["name"].empty? ? state["name"] : "(unnamed)"
      udid = hardware["udid"].to_s
      next if !wanted.empty? && ![name, udid, identifier].any? { |value| value.downcase == wanted }

      Selection.new(
        identifier: identifier,
        name: name,
        connection: connection["state"].to_s.empty? ? "unknown" : connection["state"],
      )
    end

    if candidates.empty?
      if wanted.empty?
        raise Error, "no physical iOS device found. Pair or plug in an iPhone, unlock it, and trust this Mac."
      end
      raise Error, %(no physical iOS device matching "#{filter}". Run `xcrun devicectl list devices` to see what's paired.)
    end
    if candidates.length > 1
      listing = candidates.map { |candidate| "  - #{candidate.name} (#{candidate.identifier}) [#{candidate.connection}]" }.join("\n")
      raise Error, "multiple physical iOS devices; pass --device <name|udid>:\n#{listing}"
    end

    candidates.fetch(0)
  rescue JSON::ParserError => error
    raise Error, "couldn't read devicectl's device list (#{error.message}). Run `xcrun devicectl list devices` to check your setup."
  end
end

def device_selection_main(arguments)
  filter = ""
  parser = OptionParser.new do |options|
    options.on("--filter VALUE") { |value| filter = value }
  end
  parser.parse!(arguments)
  selection = DeviceSelection.select(json: $stdin.read, filter: filter)
  warn "    using: #{selection.name} (#{selection.identifier})"
  $stdout.write("#{selection.identifier}\t#{selection.name}")
  0
rescue DeviceSelection::Error, OptionParser::ParseError => error
  warn "error: #{error.message}"
  1
end

exit(device_selection_main(ARGV)) if __FILE__ == $PROGRAM_NAME
