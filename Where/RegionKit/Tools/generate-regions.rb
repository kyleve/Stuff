#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates RegionKit's subdivision and bloc boundary files and the `regions.json`
# manifest that `RegionCatalog` loads.
#
# The installed release under Tools/source/release pins the normalized US and
# Canadian inputs. The European Union uses the checked-in outline alongside it.
# See the RegionKit README for refresh, offline replay and adoption commands.

require "json"
require "zlib"
require "fileutils"
require "tmpdir"
require_relative "../../../Tools/file_transaction"
require_relative "tiny_wkb"

# Source inputs (not bundled) live next to this script; generated output goes
# into the bundled Resources directory.
SOURCE = File.join(__dir__, "source")
RESOURCES = File.expand_path("../Sources/Resources", __dir__)

# Where's existing US tracking choices.
US_TRACKING_CODES = %w[
  AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT
  NE NV NH NJ NM NY NC ND OH OK OR PA PR RI SC SD TN TX UT VT VA WA WV WI WY
].freeze

# The handful of regions that already carry a translated string-catalog entry
# (`Localizable.xcstrings`). Everything else falls back to the manifest `name`
# (state names are proper nouns we ship in English). Keyed by region id.
LOCALIZATION_KEYS = {
  "us-CA" => "region.california",
  "us-NY" => "region.newYork",
  "canada" => "region.canada",
  "european-union" => "region.europeanUnion"
}.freeze

class RegionGenerator
  GEOMETRY_GROUPS = { "united-states" => "us", "canada" => "ca", "european-union" => "eu" }.freeze

  def self.geometry_file(id, parent, source)
    group = GEOMETRY_GROUPS.fetch(parent || id) { raise ArgumentError, "Unknown geometry group for #{id}" }
    extension = %w[census statcan].include?(source) ? ".twkb" : ".geojson"
    File.join(group, id + extension)
  end

  def initialize(source: SOURCE, resources: RESOURCES)
    @source = source
    @resources = resources
    @regions_directory = File.join(resources, "regions")
  end

  def run(release: File.join(@source, "release"))
    features = Zlib::GzipReader.open(File.join(release, "north-america.geojson.gz")) do |gz|
      JSON.parse(gz.read).fetch("features")
    end
    lock = JSON.parse(File.binread(File.join(release, "sources.lock.json")))
    features.each do |feature|
      properties = feature.fetch("properties")
      source = properties.fetch("source")
      parent = { "census" => "united-states", "statcan" => "canada" }.fetch(source)
      unless properties["parentID"] == parent && properties.fetch("kind") != "country"
        raise ArgumentError, "Expected a subdivision of #{parent} in the normalized release"
      end
      year = source == "census" ? "usYear" : "caYear"
      properties["sourceYear"] = lock.fetch(year)
    end
    eu = JSON.parse(File.read(File.join(@source, "europeanUnion.geojson"))).fetch("features").fetch(0)
    eu["properties"] = { "id" => "european-union", "name" => "European Union",
                         "kind" => "bloc", "isLoggable" => true, "source" => "original" }
    states, provinces = features.partition { |feature| feature.fetch("properties").fetch("parentID") == "united-states" }
    canada = country("canada", "Canada", "statcan", lock.fetch("caYear"), loggable: true)
    us = country("united-states", "United States", "census", lock.fetch("usYear"), loggable: false)
    generate(states + [canada] + provinces + [us, eu])
  end

  # Accept normalized, ordered GeoJSON features from a source adapter.
  def generate(features)
    manifest = features.map { |feature| manifest_entry(feature) }
    validate_hierarchy(manifest)

    FileUtils.mkdir_p(@resources)
    Dir.mktmpdir(".region-generator-", @resources) do |staging|
      staged_regions = File.join(staging, "regions")
      staged_manifest = File.join(staging, "regions.json")
      FileUtils.mkdir(staged_regions)
      features.zip(manifest).each do |feature, entry|
        file = entry["geometryFile"]
        next unless file
        path = File.join(staged_regions, file)
        FileUtils.mkdir_p(File.dirname(path))
        geometry = feature.fetch("geometry")
        if file.end_with?(".twkb")
          File.binwrite(path, TinyWKB.encode(geometry))
        else
          document = region_document(id: entry.fetch("id"), name: entry.fetch("name"), geometry: geometry)
          File.write(path, JSON.generate(document) + "\n")
        end
      end
      File.write(staged_manifest, JSON.pretty_generate(manifest) + "\n")
      transaction = FileTransaction.new
      transaction.replace(target: @regions_directory, staged: staged_regions)
      transaction.replace(target: File.join(@resources, "regions.json"), staged: staged_manifest)
      transaction.commit
    end

    files = manifest.count { |entry| entry.key?("geometryFile") }
    puts "Wrote #{files} geometry files and #{manifest.length} catalog nodes to #{@resources}"
    manifest
  end

  private

  def country(id, name, source, year, loggable:)
    { "properties" => { "id" => id, "name" => name, "kind" => "country", "isLoggable" => loggable,
                         "source" => source, "sourceYear" => year } }
  end

  # A single-feature FeatureCollection wrapping `geometry`, tagged with the
  # region id and display name for provenance (the loader reads geometry only).
  def region_document(id:, name:, geometry:)
    {
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "properties" => { "region" => id, "name" => name },
          "geometry" => geometry
        }
      ]
    }
  end

  def manifest_entry(feature)
    properties = feature.fetch("properties")
    id = properties.fetch("id")
    unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z/) && id != "other"
      raise ArgumentError, "Invalid region ID #{id.inspect}"
    end
    name = properties.fetch("name")
    raise ArgumentError, "Missing region name for #{id}" unless name.is_a?(String) && !name.empty?
    parent_id = properties["parentID"]
    raise ArgumentError, "Invalid parent ID for #{id}" unless parent_id.nil? || parent_id.is_a?(String)
    kind = properties.fetch("kind")
    unless %w[state federalDistrict territory province country bloc].include?(kind)
      raise ArgumentError, "Unknown region kind #{kind.inspect} for #{id}"
    end
    unless [true, false].include?(properties.fetch("isLoggable"))
      raise ArgumentError, "Invalid logging eligibility for #{id}"
    end
    entry = properties.slice("id", "name", "kind", "isLoggable", "parentID", "source", "sourceYear")
    key = LOCALIZATION_KEYS[id]
    entry["localizationKey"] = key if key
    if kind == "country"
      raise ArgumentError, "Country #{id} cannot carry geometry" if feature["geometry"]
    else
      geometry = feature.fetch("geometry")
      unless geometry && %w[Polygon MultiPolygon].include?(geometry["type"]) && !geometry.fetch("coordinates").empty?
        raise ArgumentError, "Missing polygon geometry for #{id}"
      end
      entry["geometryFile"] = RegionGenerator.geometry_file(id, parent_id, entry["source"])
    end
    entry
  end

  def validate_hierarchy(manifest)
    parents = {}
    manifest.each do |entry|
      id = entry.fetch("id")
      raise ArgumentError, "Duplicate region ID #{id}" if parents.key?(id)
      parents[id] = entry["parentID"]
    end
    parents.each_key do |id|
      seen = { id => true }
      ancestor = parents[id]
      while ancestor
        raise ArgumentError, "Missing parent #{ancestor} of #{id}" unless parents.key?(ancestor)
        raise ArgumentError, "Cyclic region hierarchy at #{ancestor}" if seen.key?(ancestor)
        seen[ancestor] = true
        ancestor = parents[ancestor]
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require_relative "region_release"
  begin
    RegionRelease.new.run(ARGV)
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
