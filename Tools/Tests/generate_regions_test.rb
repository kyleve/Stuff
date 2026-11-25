# frozen_string_literal: true
require_relative '../repository'

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../../Where/RegionKit/Tools/generate-regions", __dir__)

class GenerateRegionsTest < Minitest::Test
  REPOSITORY = Repository.root(__FILE__)

  def test_rejects_missing_normalized_sources_before_writing_resources
    Dir.mktmpdir do |root|
      generator = RegionGenerator.new(source: root, resources: File.join(root, "resources"))
      assert_raises(Errno::ENOENT) { generator.run }
      refute_path_exists File.join(root, "resources")
    end
  end

  def test_metadata_only_countries_and_explicit_parent_links_survive_generation
    Dir.mktmpdir do |resources|
      generator = RegionGenerator.new(resources: resources)
      country = normalized("united-states", "country", false)
      state = normalized("us-CA", "state", true, "united-states")
      canada = normalized("canada", "country", true)
      capture_io { generator.generate([state, country, canada]) }
      manifest = JSON.parse(File.read(File.join(resources, "regions.json")))
      assert_equal %w[us-CA united-states canada], manifest.map { |entry| entry.fetch("id") }
      assert_equal "united-states", manifest.first.fetch("parentID")
      refute manifest[1].fetch("isLoggable")
      assert_equal "country", manifest[1].fetch("kind")
      refute manifest.last.key?("parentID")
      assert_equal "us/us-CA.geojson", manifest.first.fetch("geometryFile")
      assert_equal ["us"], Dir.children(File.join(resources, "regions"))
      assert_equal ["us-CA.geojson"], Dir.children(File.join(resources, "regions/us"))
      refute manifest[1].key?("geometryFile")
      refute manifest.last.key?("geometryFile")

      previous = generated_files(resources)
      [
        [state], [state, country, country], [normalized("other", "country", false)],
        [state, normalized("united-states", "country", false, "us-CA")],
        [country.merge("geometry" => state.fetch("geometry"))],
        [country, state.merge("geometry" => nil)],
      ].each do |invalid|
        assert_raises(ArgumentError) { generator.generate(invalid) }
        assert_equal previous, generated_files(resources)
      end
      assert_raises(KeyError) { generator.generate([country, state.reject { |key, _| key == "geometry" }]) }
      assert_equal previous, generated_files(resources)
    end
  end

  def test_real_inputs_reproduce_every_committed_resource_byte_for_byte
    Dir.mktmpdir do |root|
      resources = File.join(root, "resources")
      capture_io { RegionGenerator.new(resources: resources).run }

      committed = File.join(REPOSITORY, "Where", "RegionKit", "Sources", "Resources")
      expected = generated_files(committed).select do |path, _contents|
        path == "regions.json" || path.start_with?("regions/")
      end
      assert_equal expected, generated_files(resources)
    end
  end

  def test_surfaces_a_manifest_write_failure
    Dir.mktmpdir do |root|
      generator = RegionGenerator.new(resources: File.join(root, "resources"))
      original_write = File.method(:write)
      failing_write = lambda do |path, *arguments|
        raise Errno::ENOSPC, path if path.end_with?("regions.json")
        original_write.call(path, *arguments)
      end

      error = File.stub(:write, failing_write) do
        assert_raises(Errno::ENOSPC) { capture_io { generator.generate([normalized("canada", "country", true)]) } }
      end
      assert_includes error.message, "regions.json"
    end
  end

  def test_tiny_wkb_keeps_ring_precision_and_deltas_across_members
    rings = [
      [[[0.0, 0.0], [2e-7, 0.0], [0.0, 2e-7], [0.0, 0.0]]],
      [[[-3e-7, 0.0], [-2e-7, 0.0], [-3e-7, 1e-7], [-3e-7, 0.0]]]
    ]
    bytes = TinyWKB.encode("type" => "MultiPolygon", "coordinates" => rings)
    assert_equal [0xe6, 0, 2, 1, 3, 0, 0, 4, 0, 3, 4, 1, 3, 5, 3, 2, 0, 1, 2], bytes.bytes
    rings.first.first[1] = [2.4e-7, 0.0]
    assert_raises(RuntimeError) { TinyWKB.encode("type" => "MultiPolygon", "coordinates" => rings) }
  end

  private

  def normalized(id, kind, loggable, parent = nil)
    properties = { "id" => id, "name" => id, "kind" => kind, "isLoggable" => loggable }
    properties["parentID"] = parent if parent
    return { "properties" => properties } if kind == "country"
    feature(nil, [[[0, 0], [1, 0], [0, 1], [0, 0]]]).merge("properties" => properties)
  end

  def feature(name, coordinates)
    properties = {}
    properties["NAME"] = name if name
    {
      "type" => "Feature",
      "properties" => properties,
      "geometry" => { "type" => "Polygon", "coordinates" => coordinates },
    }
  end

  def generated_files(resources)
    Dir[File.join(resources, "**", "*")].select { |path| File.file?(path) }.sort.to_h do |path|
      [path.delete_prefix("#{resources}/"), File.binread(path)]
    end
  end
end
