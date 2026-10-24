#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "digest"
require "json"

module ThrowAirports
  ROOT = File.expand_path("..", __dir__)
  SOURCE = File.join(__dir__, "source")
  MANIFEST = File.join(SOURCE, "airports-manifest.json")
  OUTPUT = File.join(ROOT, "Sources", "Resources", "airports-v1.json")

  class SourceError < StandardError; end

  # Builds ThrowCore's compact airport archive from pinned OurAirports CSV files.
  class Generator
    def initialize(manifest: MANIFEST, source_directory:, output: OUTPUT)
      @manifest_path = manifest
      @source_directory = source_directory
      @output = output
    end

    def run
      manifest = JSON.parse(File.binread(@manifest_path))
      airport_path = source_path(manifest.fetch("inputs").fetch("airports"))
      runway_path = source_path(manifest.fetch("inputs").fetch("runways"))
      runways = load_runways(runway_path)
      airports = load_airports(airport_path, runways)
      document = {
        "v" => manifest.fetch("archiveVersion"),
        "revision" => manifest.fetch("revision"),
        "airports" => airports,
      }
      data = JSON.generate(document) + "\n"
      digest = Digest::SHA256.hexdigest(data)
      emitted_runway_count = airports.sum { |airport| airport.fetch(5).length }
      validate_output(manifest.fetch("expectedOutput"), airports.length, emitted_runway_count, digest)

      File.binwrite(@output, data)
      puts "Wrote #{airports.length} airports and #{emitted_runway_count} runways to #{@output}"
      puts "SHA-256: #{digest}"
      data
    end

    private

    def source_path(specification)
      path = File.join(@source_directory, specification.fetch("file"))
      raise SourceError, "Missing #{path}" unless File.file?(path)

      digest = Digest::SHA256.file(path).hexdigest
      expected = specification.fetch("sha256")
      raise SourceError, "Digest mismatch for #{path}: #{digest}" unless digest == expected

      path
    end

    def load_runways(path)
      runways = Hash.new { |hash, key| hash[key] = [] }
      CSV.foreach(path, headers: true) do |row|
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
      runways
    end

    def load_airports(path, runways)
      airports = []
      CSV.foreach(path, headers: true) do |row|
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
      airports
    end

    def validate_output(expected, airport_count, runway_count, digest)
      unless airport_count == expected.fetch("airportCount")
        raise SourceError, "Generated airport count changed: #{airport_count}"
      end
      unless runway_count == expected.fetch("runwayCount")
        raise SourceError, "Generated runway count changed: #{runway_count}"
      end
      raise SourceError, "Generated digest changed: #{digest}" unless digest == expected.fetch("sha256")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    source_directory = ARGV.fetch(0) do
      abort "Usage: generate-airports.rb /path/to/ourairports-data"
    end
    ThrowAirports::Generator.new(source_directory: source_directory).run
  rescue ThrowAirports::SourceError => error
    abort error.message
  end
end
