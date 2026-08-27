# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../../Throw/ThrowCore/Tools/generate-airports"

class GenerateThrowAirportsTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_generation_counts_only_runways_in_emitted_airports
    with_fixture do |fixture|
      first = capture_io { fixture.fetch(:generator).run }.first
      first_data = File.binread(fixture.fetch(:output))
      second = capture_io { fixture.fetch(:generator).run }.first
      archive = JSON.parse(first_data)

      assert_equal first_data, File.binread(fixture.fetch(:output))
      assert_equal 1, archive.fetch("airports").length
      assert_equal 1, archive.fetch("airports").sum { |airport| airport.fetch(5).length }
      assert_includes first, "Wrote 1 airports and 1 runways"
      assert_includes second, "Wrote 1 airports and 1 runways"
    end
  end

  def test_committed_archive_matches_the_pinned_manifest_report
    manifest_path = File.join(
      REPOSITORY,
      "Throw",
      "ThrowCore",
      "Tools",
      "source",
      "airports-manifest.json",
    )
    manifest = JSON.parse(File.binread(manifest_path))
    expected = manifest.fetch("expectedOutput")
    archive_path = File.join(
      REPOSITORY,
      "Throw",
      "ThrowCore",
      "Sources",
      "Resources",
      "airports-v1.json",
    )
    data = File.binread(archive_path)
    archive = JSON.parse(data)

    assert_equal expected.fetch("sha256"), Digest::SHA256.hexdigest(data)
    assert_equal expected.fetch("airportCount"), archive.fetch("airports").length
    runway_count = archive.fetch("airports").sum { |airport| airport.fetch(5).length }
    assert_equal expected.fetch("runwayCount"), runway_count
  end

  private

  def with_fixture
    Dir.mktmpdir("throw-airports") do |directory|
      airport_path = File.join(directory, "airports.csv")
      File.binwrite(airport_path, fixture_airports)
      runway_path = File.join(directory, "runways.csv")
      File.binwrite(runway_path, fixture_runways)
      output = File.join(directory, "airports-v1.json")
      expected_data = JSON.generate(
        "v" => 1,
        "revision" => "fixture",
        "airports" => [
          [1, 10.0, 20.0, 100.0, ["KEEP"], [[11, 1_000, 10.0, 20.0, 10.1, 20.1]]],
        ],
      ) + "\n"
      manifest_path = File.join(directory, "manifest.json")
      File.binwrite(
        manifest_path,
        JSON.generate(
          "archiveVersion" => 1,
          "revision" => "fixture",
          "expectedOutput" => {
            "airportCount" => 1,
            "runwayCount" => 1,
            "sha256" => Digest::SHA256.hexdigest(expected_data),
          },
          "inputs" => {
            "airports" => fixture_input(airport_path),
            "runways" => fixture_input(runway_path),
          },
        ),
      )
      generator = ThrowAirports::Generator.new(
        manifest: manifest_path,
        source_directory: directory,
        output: output,
      )

      yield(generator: generator, output: output)
    end
  end

  def fixture_input(path)
    {
      "file" => File.basename(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
    }
  end

  def fixture_airports
    CSV.generate do |csv|
      csv << %w[id ident type latitude_deg longitude_deg elevation_ft icao_code iata_code gps_code local_code]
      csv << [1, "KEEP", "small_airport", 10, 20, 100, "", "", "", ""]
      csv << [2, "CLSD", "closed", 11, 21, 200, "", "", "", ""]
      csv << [3, "TOO_LONG", "small_airport", 12, 22, 300, "", "", "", ""]
    end
  end

  def fixture_runways
    CSV.generate do |csv|
      csv << %w[id airport_ident closed length_ft le_latitude_deg le_longitude_deg he_latitude_deg he_longitude_deg]
      csv << [11, "KEEP", 0, 1_000, 10, 20, 10.1, 20.1]
      csv << [12, "KEEP", 1, 900, 10, 20, 10.1, 20.1]
      csv << [13, "CLSD", 0, 800, 11, 21, 11.1, 21.1]
      csv << [14, "TOO_LONG", 0, 700, 12, 22, 12.1, 22.1]
    end
  end
end
