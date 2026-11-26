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
  NORMALIZED = { "tracking" => "north-america.geojson.gz", "display" => "north-america-display.geojson.gz" }.freeze
  PRODUCTS = {
    "united-states" => { "tracking" => "censusTIGER", "display" => "censusCartographic" },
    "canada" => { "tracking" => "statcanDigital", "display" => "statcanCartographic" },
  }.freeze
  YEARS = { "censusTIGER" => "usYear", "censusCartographic" => "usDisplayYear",
            "statcanDigital" => "caYear", "statcanCartographic" => "caYear" }.freeze

  def self.geometry_file(id, parent, purpose)
    return "eu/european-union.geojson" if id == "european-union" && parent.nil?
    group = { "united-states" => "us", "canada" => "ca" }.fetch(parent)
    "#{group}/#{id}.#{purpose}.twkb"
  end

  def initialize(source: SOURCE, resources: RESOURCES)
    @source = source
    @resources = resources
    @regions_directory = File.join(resources, "regions")
  end

  def run(release: File.join(@source, "release"))
    lock = JSON.parse(File.binread(File.join(release, "sources.lock.json")))
    # Keep the tracking catalog's order and names. The display product can have
    # a different vintage or order. Join the two by the stable subdivision ID.
    by_id = {}
    NORMALIZED.each do |purpose, filename|
      seen = {}
      features = Zlib::GzipReader.open(File.join(release, filename)) { |gz| JSON.parse(gz.read).fetch("features") }
      features.each do |feature|
        properties = feature.fetch("properties")
        id = properties.fetch("id")
        parent = properties.fetch("parentID")
        product = PRODUCTS.dig(parent, purpose)
        unless product && properties.fetch("source") == product && properties.fetch("kind") != "country"
          raise ArgumentError, "Expected a subdivision with the #{purpose} product for #{id}"
        end
        raise ArgumentError, "Duplicate #{purpose} region #{id}" if seen[id]
        seen[id] = true
        if purpose == "tracking"
          by_id[id] = { "properties" => properties, "boundaries" => {} }
        end
        node = by_id.fetch(id) { raise ArgumentError, "Unexpected display region #{id}" }
        keys = %w[id parentID isLoggable kind]
        raise ArgumentError, "Mismatched #{purpose} region #{id}" unless node.fetch("properties").slice(*keys) == properties.slice(*keys)
        node.fetch("boundaries")[purpose] = {
          "geometry" => feature.fetch("geometry"), "product" => product, "year" => lock.fetch(YEARS.fetch(product))
        }
      end
      raise ArgumentError, "Missing #{purpose} regions" unless by_id.keys.sort == seen.keys.sort
    end
    original = JSON.parse(File.read(File.join(@source, "europeanUnion.geojson"))).fetch("features").fetch(0)
    shared = { "geometry" => original.fetch("geometry"), "product" => "original" }
    eu = { "properties" => { "id" => "european-union", "name" => "European Union", "kind" => "bloc", "isLoggable" => true },
           "boundaries" => { "tracking" => shared, "display" => shared } }
    states, provinces = by_id.values.partition { |feature| feature.fetch("properties").fetch("parentID") == "united-states" }
    generate(states + [country("canada", "Canada")] + provinces + [country("united-states", "United States"), eu])
  end

  def generate(features)
    manifest = features.map { |feature| manifest_entry(feature) }
    validate_hierarchy(manifest)

    FileUtils.mkdir_p(@resources)
    Dir.mktmpdir(".region-generator-", @resources) do |staging|
      staged_regions = File.join(staging, "regions")
      staged_manifest = File.join(staging, "regions.json")
      FileUtils.mkdir(staged_regions)
      features.zip(manifest).each do |feature, entry|
        next unless entry["geometry"]
        written = []
        entry.fetch("geometry").each do |purpose, descriptor|
          file = descriptor.fetch("file")
          next if written.include?(file)
          written << file
          path = File.join(staged_regions, file)
          FileUtils.mkdir_p(File.dirname(path))
          geometry = feature.fetch("boundaries").fetch(purpose).fetch("geometry")
          if file.end_with?(".twkb")
            File.binwrite(path, TinyWKB.encode(geometry))
          else
            document = region_document(id: entry.fetch("id"), name: entry.fetch("name"), geometry: geometry)
            File.write(path, JSON.generate(document) + "\n")
          end
        end
      end
      File.write(staged_manifest, JSON.pretty_generate(manifest) + "\n")
      transaction = FileTransaction.new
      transaction.replace(target: @regions_directory, staged: staged_regions)
      transaction.replace(target: File.join(@resources, "regions.json"), staged: staged_manifest)
      transaction.commit
    end

    files = manifest.flat_map { |entry| entry.fetch("geometry", {}).values.map { |descriptor| descriptor.fetch("file") } }.uniq.size
    puts "Wrote #{files} geometry files and #{manifest.length} catalog nodes to #{@resources}"
    manifest
  end

  private

  def country(id, name)
    { "properties" => { "id" => id, "name" => name, "kind" => "country", "isLoggable" => false } }
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
    entry = properties.slice("id", "name", "kind", "isLoggable", "parentID")
    key = LOCALIZATION_KEYS[id]
    entry["localizationKey"] = key if key
    if kind == "country"
      raise ArgumentError, "Country #{id} cannot be loggable" if entry.fetch("isLoggable")
      raise ArgumentError, "Country #{id} cannot carry geometry" if feature["boundaries"]
    else
      boundaries = feature.fetch("boundaries")
      raise ArgumentError, "Missing purpose for #{id}" unless boundaries.keys.sort == NORMALIZED.keys.sort
      entry["geometry"] = boundaries.to_h do |purpose, boundary|
        geometry = boundary.fetch("geometry")
        unless geometry && %w[Polygon MultiPolygon].include?(geometry["type"]) && !geometry.fetch("coordinates").empty?
          raise ArgumentError, "Missing #{purpose} polygon geometry for #{id}"
        end
        descriptor = { "file" => RegionGenerator.geometry_file(id, parent_id, purpose), "product" => boundary.fetch("product") }
        descriptor["year"] = boundary.fetch("year") unless descriptor.fetch("product") == "original"
        [purpose, descriptor]
      end
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
