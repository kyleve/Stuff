#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates ThrowCore's compact offline geography archive from pinned Natural
# Earth GeoJSON inputs. Run this file from the repository root.

require "digest"
require "json"
require "fileutils"

module ThrowGeography
  SOURCE_DIRECTORY = File.join(__dir__, "source", "natural-earth-v5.1.2")
  OUTPUT = File.expand_path("../Sources/Resources/geography-v1.json", __dir__)
  COORDINATE_SCALE = 10_000
  MAXIMUM_SEGMENT_NAUTICAL_MILES = 10.0
  MAXIMUM_OUTPUT_BYTES = 2_000_000

  SOURCE_SPECS = [
    {
      file: "ne_50m_coastline.geojson",
      kind: "coastline",
      sha256: "271f1c4c1908312bac6b29d158ea1356544beafc129f260005300913aa5ea283"
    },
    {
      file: "ne_50m_lakes.geojson",
      kind: "lake",
      sha256: "d350b75978b26fe839b797c2c529b2fb8f47fb3983c03f4964e36d5df9378a52"
    },
    {
      file: "ne_50m_rivers_lake_centerlines.geojson",
      kind: "river",
      sha256: "f286e0ce978fde999ca2d7a78c764be08542e19b63cded52b05c12d5173ccc51"
    },
    {
      file: "ne_50m_admin_0_boundary_lines_land.geojson",
      kind: "national-boundary",
      sha256: "2faac4f6b34386f3d21b6e018cf151f241f00e5c936d44dd17d7d9bfb147fa48"
    },
    {
      file: "ne_50m_admin_1_states_provinces_lines.geojson",
      kind: "regional-boundary",
      sha256: "72cca93c850d412628a5da4bc5ebfe21ba4d376eb34611bde6b623ee73f0fdcf"
    }
  ].freeze

  class Generator
    def initialize(source_directory: SOURCE_DIRECTORY, output: OUTPUT)
      @source_directory = source_directory
      @output = output
    end

    def run
      paths = SOURCE_SPECS.flat_map { |spec| paths_for(spec) }
      archive = {
        "version" => 1,
        "coordinateScale" => COORDINATE_SCALE,
        "source" => {
          "name" => "Natural Earth Vector",
          "release" => "5.1.2",
          "scale" => "1:50m",
          "credit" => "Made with Natural Earth.",
          "homepageURL" => "https://www.naturalearthdata.com/",
          "termsURL" => "https://www.naturalearthdata.com/about/terms-of-use/"
        },
        "paths" => paths
      }
      data = JSON.generate(archive) + "\n"
      abort("Generated geography exceeds #{MAXIMUM_OUTPUT_BYTES} bytes") if data.bytesize > MAXIMUM_OUTPUT_BYTES

      FileUtils.mkdir_p(File.dirname(@output))
      File.binwrite(@output, data)
      puts "Wrote #{paths.length} paths and #{data.bytesize} bytes to #{@output}"
      data
    end

    private

    def paths_for(spec)
      path = File.join(@source_directory, spec.fetch(:file))
      verify_digest(path, spec.fetch(:sha256))
      document = JSON.parse(File.binread(path))
      document.fetch("features").flat_map do |feature|
        properties = feature.fetch("properties")
        kind = line_kind(spec.fetch(:kind), properties)
        minimum_zoom = properties["min_zoom"] || properties["MIN_ZOOM"] || 0
        scale_rank = properties["scalerank"] || properties["SCALERANK"] || 0
        geometry_paths(feature.fetch("geometry")).flat_map do |coordinates|
          split_antimeridian(coordinates).filter_map do |split_path|
            encoded_path(
              split_path,
              kind: kind,
              minimum_zoom: minimum_zoom,
              scale_rank: scale_rank
            )
          end
        end
      end
    end

    def verify_digest(path, expected)
      actual = Digest::SHA256.file(path).hexdigest
      return if actual == expected

      abort("Unexpected SHA-256 for #{path}: #{actual}")
    end

    def line_kind(default_kind, properties)
      return default_kind unless default_kind == "national-boundary"
      return default_kind if properties["featurecla"] == "International boundary (verify)"
      return default_kind if properties["FEATURECLA"] == "International boundary (verify)"

      "disputed-boundary"
    end

    def geometry_paths(geometry)
      coordinates = geometry.fetch("coordinates")
      case geometry.fetch("type")
      when "LineString"
        [coordinates]
      when "MultiLineString", "Polygon"
        coordinates
      when "MultiPolygon"
        coordinates.flatten(1)
      else
        abort("Unsupported Natural Earth geometry: #{geometry.fetch("type")}")
      end
    end

    def split_antimeridian(coordinates)
      return [] if coordinates.length < 2

      paths = []
      current = [coordinates.first]
      coordinates.each_cons(2) do |start_point, end_point|
        start_longitude, start_latitude = start_point
        end_longitude, end_latitude = end_point
        delta = end_longitude - start_longitude
        if delta.abs <= 180
          current << end_point
          next
        end

        adjusted_end = delta > 180 ? end_longitude - 360 : end_longitude + 360
        boundary = delta > 180 ? -180.0 : 180.0
        fraction = (boundary - start_longitude) / (adjusted_end - start_longitude)
        boundary_latitude = start_latitude + (end_latitude - start_latitude) * fraction
        current << [boundary, boundary_latitude]
        paths << current if current.length >= 2
        opposite_boundary = boundary == 180.0 ? -180.0 : 180.0
        current = [[opposite_boundary, boundary_latitude], end_point]
      end
      paths << current if current.length >= 2
      paths
    end

    def encoded_path(coordinates, kind:, minimum_zoom:, scale_rank:)
      densified = densify(coordinates)
      quantized = densified.map { |longitude, latitude| quantized_point(latitude, longitude) }
      quantized = quantized.each_with_object([]) do |point, unique|
        unique << point if unique.last != point
      end
      return nil if quantized.length < 2

      latitudes = quantized.map(&:first)
      longitudes = quantized.map(&:last)
      {
        "kind" => kind,
        "minimumZoomTenths" => (Float(minimum_zoom) * 10).round,
        "scaleRank" => Integer(scale_rank),
        "bounds" => [latitudes.min, longitudes.min, latitudes.max, longitudes.max],
        "coordinates" => delta_coordinates(quantized)
      }
    end

    def densify(coordinates)
      result = [coordinates.first]
      coordinates.each_cons(2) do |start_point, end_point|
        segment_count = [(distance_nautical_miles(start_point, end_point) /
          MAXIMUM_SEGMENT_NAUTICAL_MILES).ceil, 1].max
        (1..segment_count).each do |index|
          fraction = index.fdiv(segment_count)
          result << [
            start_point[0] + (end_point[0] - start_point[0]) * fraction,
            start_point[1] + (end_point[1] - start_point[1]) * fraction
          ]
        end
      end
      result
    end

    def distance_nautical_miles(start_point, end_point)
      longitude1, latitude1 = start_point.map { |value| value * Math::PI / 180 }
      longitude2, latitude2 = end_point.map { |value| value * Math::PI / 180 }
      delta_latitude = latitude2 - latitude1
      delta_longitude = longitude2 - longitude1
      haversine = Math.sin(delta_latitude / 2)**2 +
        Math.cos(latitude1) * Math.cos(latitude2) * Math.sin(delta_longitude / 2)**2
      central_angle = 2 * Math.asin(Math.sqrt([[haversine, 0].max, 1].min))
      3_440.069_546_436_138 * central_angle
    end

    def quantized_point(latitude, longitude)
      [(latitude * COORDINATE_SCALE).round, (longitude * COORDINATE_SCALE).round]
    end

    def delta_coordinates(points)
      previous_latitude, previous_longitude = points.first
      values = [previous_latitude, previous_longitude]
      points.drop(1).each do |latitude, longitude|
        values << latitude - previous_latitude
        values << longitude - previous_longitude
        previous_latitude = latitude
        previous_longitude = longitude
      end
      values
    end
  end
end

ThrowGeography::Generator.new.run if __FILE__ == $PROGRAM_NAME
