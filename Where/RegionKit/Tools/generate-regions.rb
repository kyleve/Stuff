#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates RegionKit's per-region GeoJSON files and the `regions.json`
# manifest that `RegionCatalog` loads.
#
# It reads the (non-bundled) source data under `Tools/source/`:
#   - `us-states.geojson` — a Census FeatureCollection (50 states + DC + PR),
#     one MultiPolygon feature per state keyed by `properties.NAME`.
#   - `canada.geojson`, `europeanUnion.geojson` — hand-simplified single-polygon
#     outlines for the non-US regions.
#
# and writes, into `Sources/Resources/`:
#   - `regions/<id>.geojson` — one file per available region (a FeatureCollection
#     with a single feature carrying `properties.region`/`properties.name`), so
#     the attributor can load only the regions it needs.
#   - `regions.json` — an ordered manifest: `{ id, name, localizationKey?,
#     geometry: { file } }`. Array order is the catalog's canonical order
#     (US states alphabetically, then countries/blocs; blocs last).
#
# Region ids are stable data identifiers, never shown to the user (names come
# from `name`/`localizationKey`): US states are `us-<USPS>` (e.g. `us-CA`),
# countries/blocs use a slug (`canada`, `european-union`).
#
# Idempotent: re-run after changing the source data. Run from the repo root:
#   ruby Where/RegionKit/Tools/generate-regions.rb

require "json"
require "fileutils"

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
  { source: "canada.geojson", id: "canada", name: "Canada" },
  { source: "europeanUnion.geojson", id: "european-union", name: "European Union" }
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

  def run
    FileUtils.rm_rf(@regions_directory)
    FileUtils.mkdir_p(@regions_directory)

    manifest = us_manifest_entries + non_us_manifest_entries
    manifest_path = File.join(@resources, "regions.json")
    File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

    puts "Wrote #{manifest.length} region files to #{@regions_directory}"
    puts "Wrote manifest with #{manifest.length} entries to #{manifest_path}"
    manifest
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

  def write_region_file(id:, name:, geometry:)
    path = File.join(@regions_directory, "#{id}.geojson")
    File.write(path, JSON.generate(region_document(id: id, name: name, geometry: geometry)) + "\n")
  end

  def manifest_entry(id:, name:)
    entry = { "id" => id, "name" => name }
    key = @localization_keys[id]
    entry["localizationKey"] = key if key
    entry["geometry"] = { "file" => "#{id}.geojson" }
    entry
  end

  def us_manifest_entries
    # US states, alphabetically by Census NAME.
    us = load_feature_collection("us-states.geojson")
    us.fetch("features").sort_by { |feature| feature.fetch("properties").fetch("NAME") }.map do |feature|
      name = feature.fetch("properties").fetch("NAME")
      usps = @usps.fetch(name) { abort("No USPS code for US feature #{name.inspect}") }
      id = "us-#{usps}"
      write_region_file(id: id, name: name, geometry: feature.fetch("geometry"))
      manifest_entry(id: id, name: name)
    end
  end

  def non_us_manifest_entries
    # Countries / blocs preserve their declared order after the US states.
    @non_us.map do |region|
      feature_collection = load_feature_collection(region.fetch(:source))
      geometry = feature_collection.fetch("features").fetch(0).fetch("geometry")
      write_region_file(id: region.fetch(:id), name: region.fetch(:name), geometry: geometry)
      manifest_entry(id: region.fetch(:id), name: region.fetch(:name))
    end
  end
end

RegionGenerator.new.run if __FILE__ == $PROGRAM_NAME
