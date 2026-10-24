# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../../Throw/ThrowCore/Tools/generate-geography"

class GenerateThrowGeographyTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_fixture_generation_is_deterministic_strips_names_and_keeps_the_widest_duplicate
    with_fixture do |fixture|
      first = capture_io { fixture.fetch(:generator).run }.first
      first_data = File.binread(fixture.fetch(:output))
      second = capture_io { fixture.fetch(:generator).run }.first
      second_data = File.binread(fixture.fetch(:output))
      archive = JSON.parse(first_data)

      assert_equal first_data, second_data
      assert_equal 2, archive.fetch("version")
      assert_equal 2, archive.fetch("paths").length
      duplicate = archive.fetch("paths").find do |path|
        path.fetch("bounds") == [0, 0, 0, 1000]
      end
      refute_nil duplicate
      assert_equal "river", duplicate.fetch("kind")
      assert_equal "wide", duplicate.fetch("detailLevel")
      refute_includes first_data, "NAME MUST NOT SHIP"
      assert_includes first, "Wrote 2 paths"
      assert_includes second, "Wrote 2 paths"
    end
  end

  def test_generated_path_and_coordinate_caps_are_enforced
    [
      ["maximumPathCount", 1, "path count"],
      ["maximumCoordinateCount", 3, "coordinate count"],
    ].each do |key, maximum, message|
      with_fixture(archive_overrides: { key => maximum }) do |fixture|
        error = assert_raises(ThrowGeography::SourceError) do
          capture_io { fixture.fetch(:generator).run }
        end

        assert_includes error.message, message
      end
    end
  end

  def test_committed_archive_matches_the_offline_manifest_report
    manifest_path = File.join(
      REPOSITORY,
      "Throw",
      "ThrowCore",
      "Tools",
      "source",
      "manifest.json",
    )
    manifest = JSON.parse(File.binread(manifest_path))
    expected = manifest.fetch("archive").fetch("expectedOutput")
    archive_path = File.join(
      REPOSITORY,
      "Throw",
      "ThrowCore",
      "Sources",
      "Resources",
      "geography-v2.json",
    )
    data = File.binread(archive_path)
    archive = JSON.parse(data)
    natural_earth = archive.fetch("sources").find do |source|
      source.fetch("id") == "natural-earth-vector-5-1-2"
    end

    assert_equal expected.fetch("sha256"), Digest::SHA256.hexdigest(data)
    assert_equal expected.fetch("encodedBytes"), data.bytesize
    assert_equal expected.fetch("pathCount"), archive.fetch("paths").length
    coordinate_count = archive.fetch("paths").sum do |path|
      path.fetch("coordinates").length / 2
    end
    assert_equal expected.fetch("coordinateCount"), coordinate_count
    assert_equal "Made with Natural Earth.", natural_earth&.fetch("credit")
    assert natural_earth&.fetch("termsURL")
  end

  private

  def with_fixture(archive_overrides: {})
    Dir.mktmpdir("throw-geography") do |directory|
      high_file = File.join(directory, "high.geojson")
      low_file = File.join(directory, "low.geojson")
      File.binwrite(
        high_file,
        JSON.generate(
          "type" => "FeatureCollection",
          "features" => [
            feature([[0.0, 0.0], [0.1, 0.0]], "local"),
            feature([[0.1, 0.0], [0.0, 0.0]], "wide"),
            feature([[1.0, 1.0], [1.1, 1.0]], "wide"),
          ],
        ),
      )
      File.binwrite(
        low_file,
        JSON.generate(
          "type" => "FeatureCollection",
          "features" => [feature([[0.0, 0.0], [0.1, 0.0]], "wide")],
        ),
      )
      manifest_path = File.join(directory, "manifest.json")
      File.binwrite(
        manifest_path,
        JSON.generate(fixture_manifest(high_file, low_file, archive_overrides)),
      )
      output = File.join(directory, "geography-v2.json")
      generator = ThrowGeography::Generator.new(
        manifest: manifest_path,
        source_directory: directory,
        output: output,
      )

      yield(generator: generator, output: output)
    end
  end

  def fixture_manifest(high_file, low_file, archive_overrides)
    archive = {
      "version" => 2,
      "coordinateScale" => 10_000,
      "maximumSegmentNauticalMiles" => 10,
      "maximumPathCount" => 10,
      "maximumCoordinateCount" => 100,
      "maximumOutputBytes" => 1_000_000,
    }.merge(archive_overrides)
    {
      "manifestVersion" => 1,
      "archive" => archive,
      "sources" => [
        { "id" => "fixture", "name" => "Fixture", "release" => "1", "scale" => "test" },
      ],
      "inputs" => [
        fixture_input("high", high_file, priority: 20, kind: "river"),
        fixture_input("low", low_file, priority: 10, kind: "coastline"),
      ],
    }
  end

  def fixture_input(identifier, path, priority:, kind:)
    {
      "id" => identifier,
      "sourceID" => "fixture",
      "format" => "geojson",
      "archive" => {
        "file" => File.basename(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
      },
      "kind" => kind,
      "detailLevel" => {
        "strategy" => "property",
        "property" => "detail",
        "values" => { "wide" => "wide", "local" => "local" },
        "default" => "standard",
      },
      "priority" => priority,
      "deduplicationGroup" => "fixture",
      "simplificationNauticalMiles" => 0,
    }
  end

  def feature(coordinates, detail)
    {
      "type" => "Feature",
      "properties" => { "detail" => detail, "NAME" => "NAME MUST NOT SHIP" },
      "geometry" => { "type" => "LineString", "coordinates" => coordinates },
    }
  end
end
