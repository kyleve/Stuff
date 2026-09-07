# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../../Where/RegionKit/Tools/generate-regions", __dir__)

class GenerateRegionsTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_generates_ordered_manifest_and_exact_per_region_documents_idempotently
    Dir.mktmpdir do |root|
      source = File.join(root, "source")
      resources = File.join(root, "resources")
      FileUtils.mkdir_p([source, File.join(resources, "regions")])
      File.write(File.join(resources, "regions", "stale.geojson"), "stale")
      write_collection(
        File.join(source, "us-states.geojson"),
        [
          feature("California", [[[-124, 42], [-114, 42], [-114, 32], [-124, 42]]]),
          feature("Alabama", [[[-88, 35], [-85, 35], [-85, 30], [-88, 35]]]),
        ],
      )
      write_collection(File.join(source, "canada.geojson"), [feature(nil, [[[0, 0], [1, 0], [0, 0]]])])
      write_collection(File.join(source, "bloc.geojson"), [feature(nil, [[[2, 2], [3, 2], [2, 2]]])])

      generator = RegionGenerator.new(
        source: source,
        resources: resources,
        usps: { "Alabama" => "AL", "California" => "CA" },
        localization_keys: { "us-CA" => "region.california", "canada" => "region.canada" },
        non_us: [
          { source: "canada.geojson", id: "canada", name: "Canada" },
          { source: "bloc.geojson", id: "example-bloc", name: "Example Bloc" },
        ],
      )

      capture_io { generator.run }
      first_bytes = generated_files(resources)
      capture_io { generator.run }

      assert_equal first_bytes, generated_files(resources)
      refute_path_exists File.join(resources, "regions", "stale.geojson")
      manifest = JSON.parse(File.read(File.join(resources, "regions.json")))
      assert_equal %w[us-AL us-CA canada example-bloc], manifest.map { |entry| entry.fetch("id") }
      assert_nil manifest.fetch(0)["localizationKey"]
      assert_equal "region.california", manifest.fetch(1).fetch("localizationKey")
      assert_equal "region.canada", manifest.fetch(2).fetch("localizationKey")
      assert_nil manifest.fetch(3)["localizationKey"]

      california = JSON.parse(File.read(File.join(resources, "regions", "us-CA.geojson")))
      generated_feature = california.fetch("features").fetch(0)
      assert_equal({ "region" => "us-CA", "name" => "California" }, generated_feature.fetch("properties"))
      assert_equal "Polygon", generated_feature.fetch("geometry").fetch("type")
      assert_equal({ "file" => "us-CA.geojson" }, manifest.fetch(1).fetch("geometry"))
    end
  end

  def test_rejects_an_unmapped_us_feature
    Dir.mktmpdir do |root|
      source = File.join(root, "source")
      resources = File.join(root, "resources")
      FileUtils.mkdir_p(source)
      write_collection(
        File.join(source, "us-states.geojson"),
        [feature("Atlantis", [[[0, 0], [1, 0], [0, 0]]])],
      )

      _, error = capture_io do
        assert_raises(SystemExit) do
          RegionGenerator.new(
            source: source,
            resources: resources,
            usps: {},
            localization_keys: {},
            non_us: [],
          ).run
        end
      end

      assert_includes error, "No USPS code for US feature \"Atlantis\""
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
      source = File.join(root, "source")
      resources = File.join(root, "resources")
      FileUtils.mkdir_p(source)
      write_collection(
        File.join(source, "us-states.geojson"),
        [feature("Alabama", [[[-88, 35], [-85, 35], [-85, 30], [-88, 35]]])],
      )

      generator = RegionGenerator.new(
        source: source,
        resources: resources,
        usps: { "Alabama" => "AL" },
        localization_keys: {},
        non_us: [],
      )
      original_write = File.method(:write)
      failing_write = lambda do |path, *arguments|
        raise Errno::ENOSPC, path if path.end_with?("regions.json")
        original_write.call(path, *arguments)
      end

      error = File.stub(:write, failing_write) do
        assert_raises(Errno::ENOSPC) { capture_io { generator.run } }
      end
      assert_includes error.message, "regions.json"
    end
  end

  private

  def feature(name, coordinates)
    properties = {}
    properties["NAME"] = name if name
    {
      "type" => "Feature",
      "properties" => properties,
      "geometry" => { "type" => "Polygon", "coordinates" => coordinates },
    }
  end

  def write_collection(path, features)
    File.write(path, JSON.generate("type" => "FeatureCollection", "features" => features))
  end

  def generated_files(resources)
    Dir[File.join(resources, "**", "*")].select { |path| File.file?(path) }.sort.to_h do |path|
      [path.delete_prefix("#{resources}/"), File.binread(path)]
    end
  end
end
