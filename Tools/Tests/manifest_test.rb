# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../Throw/ThrowCore/Tools/geography/manifest"

class GeographyManifestTest < Minitest::Test
  def test_accepts_a_core_compatible_minimal_manifest
    manifest = ThrowGeography::SourceManifest.new(base_document)

    assert_equal 2, manifest.archive.fetch("version")
    assert_equal ["fixture-source"], manifest.sources.map { |source| source.fetch("id") }
    assert_equal ["fixture-input"], manifest.inputs.map { |input| input.fetch("id") }
    assert_equal "Fixture credit", manifest.archive_sources.first.fetch("credit")
    assert_equal "https://example.com/terms", manifest.archive_sources.first.fetch("termsURL")
  end

  def test_rejects_invalid_policy_before_source_io
    mutations = {
      "kebab-case" => ->(document) { document.fetch("sources").first["id"] = "Bad_ID" },
      "Coordinate scale" => ->(document) { document.fetch("archive")["coordinateScale"] = 1_000_000_001 },
      "Maximum segment" => ->(document) { document.fetch("archive")["maximumSegmentNauticalMiles"] = 0 },
      "coordinate grid" => lambda do |document|
        document.fetch("archive")["maximumSegmentNauticalMiles"] = 0.001
      end,
      "simplification" => lambda do |document|
        document.fetch("inputs").first["simplificationNauticalMiles"] = -0.1
      end,
      "line kind" => ->(document) { document.fetch("inputs").first["kind"] = "urban-area" },
      "unknown format" => ->(document) { document.fetch("inputs").first["format"] = "shape" },
      "unknown boundary mode" => ->(document) { document.fetch("inputs").first["boundaryMode"] = "outer" },
      "unknown deduplication mode" => lambda do |document|
        document.fetch("inputs").first["deduplicationMode"] = "first"
      end,
      "Unknown detail level" => ->(document) { document.fetch("inputs").first["detailLevel"] = "near" },
      "Unknown detail level(s)" => lambda do |document|
        document.fetch("inputs").first["detailLevel"] = {
          "strategy" => "property",
          "property" => "class",
          "values" => { "primary" => "near" },
          "default" => "wide",
        }
      end,
    }

    mutations.each do |message, mutation|
      document = deep_copy(base_document)
      mutation.call(document)

      error = assert_raises(ThrowGeography::SourceError, message) do
        ThrowGeography::SourceManifest.new(document)
      end

      assert_includes error.message, message, message
    end
  end

  def test_rejects_nonpositive_runtime_caps
    %w[maximumPathCount maximumCoordinateCount].each do |key|
      document = deep_copy(base_document)
      document.fetch("archive")[key] = 0

      error = assert_raises(ThrowGeography::SourceError) do
        ThrowGeography::SourceManifest.new(document)
      end

      assert_includes error.message, key
    end
  end

  def test_validates_the_optional_expected_output_report
    document = deep_copy(base_document)
    document.fetch("archive")["expectedOutput"] = {
      "sha256" => "a" * 64,
      "encodedBytes" => 100,
      "pathCount" => 2,
      "coordinateCount" => 4,
    }

    ThrowGeography::SourceManifest.new(document)
    document.fetch("archive").fetch("expectedOutput")["sha256"] = "not-a-digest"

    error = assert_raises(ThrowGeography::SourceError) do
      ThrowGeography::SourceManifest.new(document)
    end
    assert_includes error.message, "Expected output"
  end

  private

  def base_document
    {
      "manifestVersion" => 1,
      "archive" => {
        "version" => 2,
        "coordinateScale" => 10_000,
        "maximumSegmentNauticalMiles" => 10,
        "maximumPathCount" => 10,
        "maximumCoordinateCount" => 100,
        "maximumOutputBytes" => 1_000_000,
      },
      "sources" => [
        {
          "id" => "fixture-source",
          "name" => "Fixture",
          "release" => "1",
          "scale" => "fixture",
          "homepageURL" => "https://example.com/",
          "termsURL" => "https://example.com/terms",
          "credit" => "Fixture credit",
        },
      ],
      "inputs" => [
        {
          "id" => "fixture-input",
          "sourceID" => "fixture-source",
          "format" => "geojson",
          "archive" => { "file" => "fixture.geojson", "sha256" => "0" * 64 },
          "kind" => "coastline",
          "detailLevel" => "wide",
          "priority" => 1,
          "deduplicationGroup" => "fixture",
          "simplificationNauticalMiles" => 0,
        },
      ],
    }
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
