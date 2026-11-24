# frozen_string_literal: true
require_relative '../repository'

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../../Where/RegionKit/Tools/generate-regions", __dir__)

class GenerateRegionsTest < Minitest::Test
  REPOSITORY = Repository.root(__FILE__)

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
          { source: "canada.geojson", id: "canada", name: "Canada", kind: "country" },
          { source: "bloc.geojson", id: "example-bloc", name: "Example Bloc", kind: "bloc" },
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

  def test_normalized_features_keep_country_geometry_and_only_explicit_parent_links
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
      file = manifest[1].fetch("geometry").fetch("file")
      assert_equal country.fetch("geometry"), JSON.parse(File.read(File.join(resources, "regions", file))).fetch("features").first.fetch("geometry")

      previous = generated_files(resources)
      [
        [state], [state, country, country], [normalized("other", "country", false)],
        [state, normalized("united-states", "country", false, "us-CA")],
        [country.merge("geometry" => nil)],
      ].each do |invalid|
        assert_raises(ArgumentError) { generator.generate(invalid) }
        assert_equal previous, generated_files(resources)
      end
      assert_raises(KeyError) { generator.generate([country.reject { |key, _| key == "geometry" }]) }
      assert_equal previous, generated_files(resources)
    end
  end

  def test_source_outline_is_required_for_nonloggable_country
    Dir.mktmpdir do |root|
      generator = RegionGenerator.new(
        source: root, resources: root,
        non_us: [{ source: "missing.geojson", id: "united-states", name: "United States", kind: "country", is_loggable: false }],
      )
      assert_raises(Errno::ENOENT) { generator.source_features }
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

  def write_collection(path, features)
    File.write(path, JSON.generate("type" => "FeatureCollection", "features" => features))
  end

  def generated_files(resources)
    Dir[File.join(resources, "**", "*")].select { |path| File.file?(path) }.sort.to_h do |path|
      [path.delete_prefix("#{resources}/"), File.binread(path)]
    end
  end
end
