#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "digest"
require "json"

ROOT = File.expand_path("..", __dir__)
SOURCE = File.join(__dir__, "source")
MANIFEST_PATH = File.join(SOURCE, "airports-manifest.json")
OUTPUT_PATH = File.join(ROOT, "Sources", "Resources", "airports-v1.json")

manifest = JSON.parse(File.read(MANIFEST_PATH))
source_directory = ARGV.fetch(0) do
  abort "Usage: generate-airports.rb /path/to/ourairports-data"
end

def source_path(source_directory, specification)
  path = File.join(source_directory, specification.fetch("file"))
  abort "Missing #{path}" unless File.file?(path)

  digest = Digest::SHA256.file(path).hexdigest
  expected = specification.fetch("sha256")
  abort "Digest mismatch for #{path}: #{digest}" unless digest == expected
  path
end

airport_path = source_path(source_directory, manifest.fetch("inputs").fetch("airports"))
runway_path = source_path(source_directory, manifest.fetch("inputs").fetch("runways"))

runways = Hash.new { |hash, key| hash[key] = [] }
CSV.foreach(runway_path, headers: true) do |row|
  next unless row.fetch("closed") == "0"
  next if row.fetch("le_latitude_deg").to_s.empty? || row.fetch("le_longitude_deg").to_s.empty?
  next if row.fetch("he_latitude_deg").to_s.empty? || row.fetch("he_longitude_deg").to_s.empty?

  length = row.fetch("length_ft").to_i
  next unless length.positive?

  runways[row.fetch("airport_ident")] << [
    row.fetch("id").to_i,
    length,
    row.fetch("le_latitude_deg").to_f,
    row.fetch("le_longitude_deg").to_f,
    row.fetch("he_latitude_deg").to_f,
    row.fetch("he_longitude_deg").to_f,
  ]
end

airports = []
CSV.foreach(airport_path, headers: true) do |row|
  next if row.fetch("type") == "closed"

  codes = [row.fetch("ident"), row.fetch("icao_code"), row.fetch("iata_code"),
           row.fetch("gps_code"), row.fetch("local_code")]
    .compact.reject(&:empty?).map(&:upcase)
    .select { |code| code.match?(/\A[A-Z0-9]{3,4}\z/) }.uniq.sort
  next if codes.empty?

  airports << [
    row.fetch("id").to_i,
    row.fetch("latitude_deg").to_f,
    row.fetch("longitude_deg").to_f,
    row.fetch("elevation_ft").to_s.empty? ? nil : row.fetch("elevation_ft").to_f,
    codes,
    runways.fetch(row.fetch("ident"), []).sort_by { |runway| [-runway[1], runway[0]] },
  ]
end
airports.sort_by!(&:first)

document = {
  "v" => manifest.fetch("archiveVersion"),
  "revision" => manifest.fetch("revision"),
  "airports" => airports,
}
data = JSON.generate(document) + "\n"
digest = Digest::SHA256.hexdigest(data)
expected_output = manifest.fetch("expectedOutput")
abort "Generated airport count changed: #{airports.length}" unless airports.length == expected_output.fetch("airportCount")
abort "Generated runway count changed" unless runways.values.sum(&:length) == expected_output.fetch("runwayCount")
abort "Generated digest changed: #{digest}" unless digest == expected_output.fetch("sha256")
File.binwrite(OUTPUT_PATH, data)
puts "Wrote #{airports.length} airports and #{runways.values.sum(&:length)} runways to #{OUTPUT_PATH}"
puts "SHA-256: #{digest}"
