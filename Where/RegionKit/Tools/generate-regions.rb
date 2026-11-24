#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates RegionKit's per-region GeoJSON files and the `regions.json`
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

# Census `NAME` -> USPS code, for the 50 states + DC + PR present in
# `us-states.geojson`.
USPS = {
  "Alabama" => "AL", "Alaska" => "AK", "Arizona" => "AZ", "Arkansas" => "AR",
  "California" => "CA", "Colorado" => "CO", "Connecticut" => "CT",
  "Delaware" => "DE", "District of Columbia" => "DC", "Florida" => "FL",
  "Georgia" => "GA", "Hawaii" => "HI", "Idaho" => "ID", "Illinois" => "IL",
  "Indiana" => "IN", "Iowa" => "IA", "Kansas" => "KS", "Kentucky" => "KY",
  "Louisiana" => "LA", "Maine" => "ME", "Maryland" => "MD",
  "Massachusetts" => "MA", "Michigan" => "MI", "Minnesota" => "MN",
  "Mississippi" => "MS", "Missouri" => "MO", "Montana" => "MT",
  "Nebraska" => "NE", "Nevada" => "NV", "New Hampshire" => "NH",
  "New Jersey" => "NJ", "New Mexico" => "NM", "New York" => "NY",
  "North Carolina" => "NC", "North Dakota" => "ND", "Ohio" => "OH",
  "Oklahoma" => "OK", "Oregon" => "OR", "Pennsylvania" => "PA",
  "Puerto Rico" => "PR", "Rhode Island" => "RI", "South Carolina" => "SC",
  "South Dakota" => "SD", "Tennessee" => "TN", "Texas" => "TX", "Utah" => "UT",
  "Vermont" => "VT", "Virginia" => "VA", "Washington" => "WA",
  "West Virginia" => "WV", "Wisconsin" => "WI", "Wyoming" => "WY"
}.freeze

# The handful of regions that already carry a translated string-catalog entry
# (`Localizable.xcstrings`). Everything else falls back to the manifest `name`
# (state names are proper nouns we ship in English). Keyed by region id.
LOCALIZATION_KEYS = {
  "us-CA" => "region.california",
  "us-NY" => "region.newYork",
  "canada" => "region.canada",
  "european-union" => "region.europeanUnion"
}.freeze

# Non-US source files -> (id, display name), emitted after the US states.
# Blocs come after countries so the catalog order keeps a bloc after any
# overlapping members it might gain later.
NON_US = [
  { source: "canada.geojson", id: "canada", name: "Canada", kind: "country" },
  { source: "europeanUnion.geojson", id: "european-union", name: "European Union", kind: "bloc" }
].freeze

class RegionGenerator
  def initialize(
    source: SOURCE,
    resources: RESOURCES,
    usps: USPS,
    localization_keys: LOCALIZATION_KEYS,
    non_us: NON_US
  )
    @source = source
    @resources = resources
    @regions_directory = File.join(resources, "regions")
    @usps = usps
    @localization_keys = localization_keys
    @non_us = non_us
  end

  def run(release: File.join(@source, "release"))
    return generate(us_features + source_features) unless release && Dir.exist?(release)
    features = Zlib::GzipReader.open(File.join(release, "north-america.geojson.gz")) do |gz|
      JSON.parse(gz.read).fetch("features")
    end
    lock = JSON.parse(File.binread(File.join(release, "sources.lock.json")))
    features.each do |feature|
      properties = feature.fetch("properties")
      year = { "census" => "usYear", "statcan" => "caYear" }.fetch(properties.fetch("source"))
      properties["sourceYear"] = lock.fetch(year)
    end
    bloc = source_features(@non_us.select { |region| region.fetch(:id) == "european-union" })
    bloc.each { |feature| feature.fetch("properties")["source"] = "original" }
    generate(features + bloc)
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
        file = entry.fetch("geometry").fetch("file")
        geometry = feature.fetch("geometry")
        if file.end_with?(".twkb")
          File.binwrite(File.join(staged_regions, file), TinyWKB.encode(geometry))
        else
          document = region_document(id: entry.fetch("id"), name: entry.fetch("name"), geometry: geometry)
          File.write(File.join(staged_regions, file), JSON.generate(document) + "\n")
        end
      end
      File.write(staged_manifest, JSON.pretty_generate(manifest) + "\n")
      transaction = FileTransaction.new
      transaction.replace(target: @regions_directory, staged: staged_regions)
      transaction.replace(target: File.join(@resources, "regions.json"), staged: staged_manifest)
      transaction.commit
    end

    puts "Wrote #{manifest.length} region files and manifest to #{@resources}"
    manifest
  end

  # Individually configured source outlines, in their declared catalog order.
  def source_features(regions = @non_us)
    regions.map do |region|
      collection = load_feature_collection(region.fetch(:source))
      properties = {
        "id" => region.fetch(:id), "name" => region.fetch(:name),
        "kind" => region.fetch(:kind), "isLoggable" => region.fetch(:is_loggable, true)
      }
      properties["parentID"] = region.fetch(:parent_id) if region.key?(:parent_id)
      { "type" => "Feature", "properties" => properties, "geometry" => collection.fetch("features").fetch(0).fetch("geometry") }
    end
  end

  private

  def load_feature_collection(name)
    JSON.parse(File.read(File.join(@source, name)))
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
    geometry = feature.fetch("geometry")
    unless geometry && %w[Polygon MultiPolygon].include?(geometry["type"]) && !geometry.fetch("coordinates").empty?
      raise ArgumentError, "Missing polygon geometry for #{id}"
    end
    entry = properties.slice("id", "name", "kind", "isLoggable", "parentID", "source", "sourceYear")
    key = @localization_keys[id]
    entry["localizationKey"] = key if key
    extension = %w[census statcan].include?(entry["source"]) ? ".twkb" : ".geojson"
    entry["geometry"] = { "file" => id + extension }
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

  def us_features
    us = load_feature_collection("us-states.geojson")
    us.fetch("features").sort_by { |feature| feature.fetch("properties").fetch("NAME") }.map do |feature|
      name = feature.fetch("properties").fetch("NAME")
      usps = @usps.fetch(name) { abort("No USPS code for US feature #{name.inspect}") }
      kind = { "DC" => "federalDistrict", "PR" => "territory" }.fetch(usps, "state")
      properties = { "id" => "us-#{usps}", "name" => name, "kind" => kind, "isLoggable" => true }
      { "type" => "Feature", "properties" => properties, "geometry" => feature.fetch("geometry") }
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
