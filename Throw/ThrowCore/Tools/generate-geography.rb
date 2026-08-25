#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates ThrowCore's compact offline geography archive from pinned source
# archives. Run this file from the repository root.

require "digest"
require "fileutils"
require "json"
require "optparse"

require_relative "geography/geometry_encoder"
require_relative "geography/manifest"
require_relative "geography/shapefile"
require_relative "geography/source_archive"

module ThrowGeography
  MANIFEST = File.join(__dir__, "source", "manifest.json")
  SOURCE_DIRECTORY = File.join(__dir__, "source", "cache")
  OUTPUT = File.expand_path("../Sources/Resources/geography-v2.json", __dir__)
  # Builds archive paths from the declarative source manifest.
  class Generator
    attr_reader :report

    def initialize(
      manifest: MANIFEST,
      source_directory: SOURCE_DIRECTORY,
      output: OUTPUT,
      fetch: false
    )
      @manifest_path = manifest
      @source_directory = source_directory
      @output = output
      @fetch = fetch
      @report = nil
    end

    def run
      manifest = SourceManifest.load(@manifest_path)
      archive_specification = manifest.archive
      coordinate_scale = Integer(archive_specification.fetch("coordinateScale"))
      maximum_segment_nm = Float(archive_specification.fetch("maximumSegmentNauticalMiles"))
      @geometry_encoder = GeometryEncoder.new(
        coordinate_scale: coordinate_scale,
        maximum_segment_nautical_miles: maximum_segment_nm,
        detail_order: SourceManifest::DETAIL_ORDER,
      )
      inputs = manifest.inputs.sort_by do |input|
        [-Integer(input.fetch("priority")), input.fetch("id")]
      end
      output_paths = []
      input_reports = {}

      inputs.each do |input|
        input_report = empty_report
        input_paths(input) do |path|
          output_paths << path
          input_report["pathCount"] += 1
          input_report["coordinateCount"] += path.fetch("coordinates").length / 2
          input_report["detailLevels"][path.fetch("detailLevel")]["pathCount"] += 1
          input_report["detailLevels"][path.fetch("detailLevel")]["coordinateCount"] +=
            path.fetch("coordinates").length / 2
        end
        input_reports[input.fetch("id")] = input_report
      end

      output_paths.sort_by! do |path|
        [
          path.fetch("kind"),
          SourceManifest::DETAIL_ORDER.fetch(path.fetch("detailLevel")),
          path.fetch("bounds"),
          path.fetch("coordinates"),
        ]
      end
      archive = {
        "version" => Integer(archive_specification.fetch("version")),
        "coordinateScale" => coordinate_scale,
        "sources" => manifest.archive_sources,
        "paths" => output_paths,
      }
      data = JSON.generate(archive) + "\n"
      @report = build_report(data, output_paths, input_reports)
      enforce_count_limit(
        "path count",
        @report.fetch("pathCount"),
        Integer(archive_specification.fetch("maximumPathCount")),
      )
      enforce_count_limit(
        "coordinate count",
        @report.fetch("coordinateCount"),
        Integer(archive_specification.fetch("maximumCoordinateCount")),
      )
      maximum_output_bytes = Integer(archive_specification.fetch("maximumOutputBytes"))
      if data.bytesize > maximum_output_bytes
        print_report("Generated")
        raise SourceError,
          "Generated geography is #{data.bytesize} bytes; limit is #{maximum_output_bytes} bytes"
      end

      FileUtils.mkdir_p(File.dirname(@output))
      File.binwrite(@output, data)
      print_report("Wrote")
      data
    end

    private

    def enforce_count_limit(label, actual, maximum)
      return if actual <= maximum

      print_report("Generated")
      raise SourceError, "Generated geography #{label} is #{actual}; limit is #{maximum}"
    end

    def input_paths(input)
      if input["boundaryMode"] == "shared-edges"
        candidates = @geometry_encoder.shared_boundary_candidates(
          kind: kind_for(input.fetch("kind"), {}),
          deduplication_group: input.fetch("deduplicationGroup"),
          input_id: input.fetch("id"),
        ) do |collector|
          each_feature(input) do |feature|
            next unless included_feature?(input, feature.properties)

            detail_level = detail_level_for(input.fetch("detailLevel"), feature.properties)
            collector.call(feature.paths, detail_level)
          end
        end
        ordered_candidates(candidates).each do |candidate|
          encoded_candidate(candidate, input).each { |path| yield path }
        end
        return
      end

      candidates = []
      each_feature(input) do |feature|
        next unless included_feature?(input, feature.properties)

        kind = kind_for(input.fetch("kind"), feature.properties)
        detail_level = detail_level_for(input.fetch("detailLevel"), feature.properties)
        feature.paths.each do |coordinates|
          @geometry_encoder.split_antimeridian(coordinates).each do |split_path|
            candidate = Candidate.new(
              coordinates: split_path,
              kind: kind,
              detail_level: detail_level,
              deduplication_group: input.fetch("deduplicationGroup"),
              input_id: input.fetch("id"),
            )
            candidates << candidate
          end
        end
      end
      candidates = @geometry_encoder.merge_connected_candidates(candidates) if input["mergeConnectedPaths"]
      ordered_candidates(candidates).each do |candidate|
        encoded_candidate(candidate, input).each { |path| yield path }
      end
    end

    def encoded_candidate(candidate, input)
      @geometry_encoder.encode(
        candidate,
        simplification_nautical_miles: Float(input.fetch("simplificationNauticalMiles")),
        deduplication_mode: input.fetch("deduplicationMode", "path"),
      )
    end

    def ordered_candidates(candidates)
      candidates.sort_by do |candidate|
        [SourceManifest::DETAIL_ORDER.fetch(candidate.detail_level), candidate.kind, candidate.coordinates]
      end
    end

    def each_feature(input)
      archive = SourceArchive.new(
        source_directory: @source_directory,
        specification: input.fetch("archive"),
        fetch: @fetch,
      )
      format = input.fetch("format")
      case format
      when "shapefile"
        shapefile_data, dbase_data = archive.shapefile_members
        ShapefileReader.new(
          shapefile_data: shapefile_data,
          dbase_data: dbase_data,
        ).each_feature { |feature| yield feature }
      when "geojson"
        document = JSON.parse(archive.bytes)
        document.fetch("features").each do |feature|
          properties = feature.fetch("properties", {})
          paths = geometry_paths(feature.fetch("geometry"))
          yield ShapefileReader::Feature.new(properties: properties, paths: paths)
        end
      else
        raise SourceError, "Unsupported source format #{format}"
      end
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
        raise SourceError, "Unsupported GeoJSON geometry #{geometry.fetch("type")}"
      end
    end

    def included_feature?(input, properties)
      included = input.fetch("includeProperties", {}).all? do |field, values|
        values.include?(property(properties, field))
      end
      excluded = input.fetch("excludeProperties", {}).any? do |field, values|
        values.include?(property(properties, field))
      end
      included && !excluded
    end

    def kind_for(specification, properties)
      return specification if specification.is_a?(String)

      value = property(properties, specification.fetch("property"))
      specification.fetch("values", {}).fetch(value.to_s, specification.fetch("default"))
    end

    def detail_level_for(specification, properties)
      return specification if specification.is_a?(String)

      case specification.fetch("strategy")
      when "natural-earth"
        natural_earth_detail(specification, properties)
      when "property"
        value = property(properties, specification.fetch("property"))
        specification.fetch("values", {}).fetch(value.to_s, specification.fetch("default"))
      when "numeric-property"
        value = Float(property(properties, specification.fetch("property")))
        rule = specification.fetch("rules").find do |candidate|
          (!candidate.key?("minimum") || value >= Float(candidate.fetch("minimum"))) &&
            (!candidate.key?("maximum") || value <= Float(candidate.fetch("maximum")))
        end
        rule ? rule.fetch("value") : specification.fetch("default")
      end.tap do |detail_level|
        unless SourceManifest::DETAIL_ORDER.key?(detail_level)
          raise SourceError, "Unknown detail level #{detail_level}"
        end
      end
    end

    def natural_earth_detail(specification, properties)
      minimum_zoom = Float(property(properties, specification.fetch("minimumZoomProperty")) || 0)
      scale_rank = Integer(property(properties, specification.fetch("scaleRankProperty")) || 0)
      wide = specification.fetch("wide")
      standard = specification.fetch("standard")
      if minimum_zoom <= Float(wide.fetch("maximumMinimumZoom")) &&
          scale_rank <= Integer(wide.fetch("maximumScaleRank"))
        "wide"
      elsif minimum_zoom <= Float(standard.fetch("maximumMinimumZoom")) &&
          scale_rank <= Integer(standard.fetch("maximumScaleRank"))
        "standard"
      else
        "local"
      end
    end

    def property(properties, requested_name)
      key = properties.keys.find { |candidate| candidate.casecmp?(requested_name) }
      key ? properties[key] : nil
    end

    def empty_report
      {
        "pathCount" => 0,
        "coordinateCount" => 0,
        "detailLevels" => SourceManifest::DETAIL_ORDER.keys.to_h do |detail_level|
          [detail_level, { "pathCount" => 0, "coordinateCount" => 0 }]
        end,
      }
    end

    def build_report(data, paths, input_reports)
      tier_reports = SourceManifest::DETAIL_ORDER.keys.to_h do |detail_level|
        selected = paths.select { |path| path.fetch("detailLevel") == detail_level }
        [
          detail_level,
          {
            "pathCount" => selected.length,
            "coordinateCount" => selected.sum { |path| path.fetch("coordinates").length / 2 },
          },
        ]
      end
      {
        "encodedBytes" => data.bytesize,
        "sha256" => Digest::SHA256.hexdigest(data),
        "pathCount" => paths.length,
        "coordinateCount" => paths.sum { |path| path.fetch("coordinates").length / 2 },
        "detailLevels" => tier_reports,
        "inputs" => input_reports,
      }
    end

    def print_report(action)
      puts "#{action} #{@report.fetch("pathCount")} paths, #{@report.fetch("coordinateCount")} coordinates, " \
        "and #{@report.fetch("encodedBytes")} bytes to #{@output}"
      puts "SHA-256: #{@report.fetch("sha256")}"
      @report.fetch("detailLevels").each do |detail_level, counts|
        puts "  #{detail_level}: #{counts.fetch("pathCount")} paths, " \
          "#{counts.fetch("coordinateCount")} coordinates"
      end
      @report.fetch("inputs").each do |input_id, counts|
        puts "  #{input_id}: #{counts.fetch("pathCount")} paths, " \
          "#{counts.fetch("coordinateCount")} coordinates"
        counts.fetch("detailLevels").each do |detail_level, detail_counts|
          next if detail_counts.fetch("pathCount").zero?

          puts "    #{detail_level}: #{detail_counts.fetch("pathCount")} paths, " \
            "#{detail_counts.fetch("coordinateCount")} coordinates"
        end
      end
    end
  end

  # Parses the standalone generator command.
  class Command
    def self.run(arguments)
      options = {
        manifest: MANIFEST,
        source_directory: SOURCE_DIRECTORY,
        output: OUTPUT,
        fetch: false,
      }
      parser = OptionParser.new do |option|
        option.banner = "Usage: ruby Throw/ThrowCore/Tools/generate-geography.rb [options]"
        option.on("--fetch", "Fetch missing or mismatched pinned archives") { options[:fetch] = true }
        option.on("--manifest PATH", "Use a different source manifest") { |path| options[:manifest] = path }
        option.on("--source-directory PATH", "Use a different source cache") do |path|
          options[:source_directory] = path
        end
        option.on("--output PATH", "Write the archive to a different path") { |path| options[:output] = path }
      end
      parser.parse!(arguments)
      raise SourceError, "Unexpected arguments: #{arguments.join(" ")}" unless arguments.empty?

      Generator.new(**options).run
    rescue OptionParser::ParseError, SourceError => error
      warn error.message
      warn parser
      1
    else
      0
    end
  end
end

exit ThrowGeography::Command.run(ARGV) if __FILE__ == $PROGRAM_NAME
