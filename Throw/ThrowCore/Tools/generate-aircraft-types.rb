#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"

module ThrowAircraftTypes
  EXPECTED_SHA256 = "46e4a4c6274176f70f204ee9cceaf132d47a408c05ebdd75d32e09e909087f0f"
  MEMBER = "icao_aircraft_types.json"
  OUTPUT = File.expand_path("../Sources/Resources/aircraft-types-v1.json", __dir__)

  class Generator
    def initialize(archive:, output: OUTPUT, expected_sha256: EXPECTED_SHA256)
      @archive = archive
      @output = output
      @expected_sha256 = expected_sha256
    end

    def run
      actual = Digest::SHA256.file(@archive).hexdigest
      raise "Archive checksum mismatch: #{actual}" unless actual == @expected_sha256

      source, error, status = Open3.capture3("unzip", "-p", @archive, MEMBER)
      raise "Cannot extract #{MEMBER}: #{error}" unless status.success?

      input = JSON.parse(source)
      types = input.keys.sort.to_h do |designator|
        record = input.fetch(designator)
        [designator, { "d" => record.fetch("desc"), "w" => record.fetch("wtc") }]
      end
      document = {
        "version" => 1,
        "source" => {
          "name" => "Mictronics aircraft-database",
          "revision" => "722ec71ad990bd75389a6626d6c3a065b02f2b6d",
          "license" => "ODC-By-1.0",
        },
        "types" => types,
      }
      data = JSON.generate(document) + "\n"
      File.binwrite(@output, data)
      puts "Wrote #{types.length} aircraft types (#{data.bytesize} bytes)"
      data
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on("--archive PATH") { |path| options[:archive] = path }
    parser.on("--output PATH") { |path| options[:output] = path }
  end.parse!
  abort "Usage: generate-aircraft-types.rb --archive PATH [--output PATH]" unless options[:archive]
  ThrowAircraftTypes::Generator.new(
    archive: options.fetch(:archive),
    output: options.fetch(:output, ThrowAircraftTypes::OUTPUT),
  ).run
end
