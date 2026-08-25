# frozen_string_literal: true

require "json"

require_relative "source_archive"

module ThrowGeography
  # Loads and validates all source and archive policy before source I/O starts.
  class SourceManifest
    MAXIMUM_OUTPUT_BYTES = 32 * 1024 * 1024
    DETAIL_ORDER = { "wide" => 0, "standard" => 1, "local" => 2 }.freeze
    LINE_KINDS = %w[
      coastline lake river national-boundary disputed-boundary regional-boundary
      county-boundary primary-road
    ].freeze

    attr_reader :archive, :inputs, :sources

    def self.load(path)
      new(JSON.parse(File.binread(path)))
    rescue KeyError, TypeError, ArgumentError, JSON::ParserError => error
      raise SourceError, "Invalid geography source manifest: #{error.message}"
    end

    def initialize(document)
      @document = document
      validate
      @archive = document.fetch("archive")
      @sources = document.fetch("sources")
      @inputs = document.fetch("inputs")
    end

    def archive_sources
      keys = %w[id name release scale homepageURL termsURL credit]
      sources.map { |source| source.slice(*keys).compact }
    end

    private

    def validate
      unless @document.fetch("manifestVersion") == 1
        raise SourceError, "Unsupported source manifest version"
      end

      validate_archive(@document.fetch("archive"))
      source_ids = validate_sources(@document.fetch("sources"))
      validate_inputs(@document.fetch("inputs"), source_ids)
    end

    def validate_archive(archive)
      raise SourceError, "Archive version must be 2" unless archive.fetch("version") == 2
      scale = Integer(archive.fetch("coordinateScale"))
      unless (1..1_000_000_000).cover?(scale)
        raise SourceError, "Coordinate scale must be from 1 through 1000000000"
      end
      maximum_segment_nm = Float(archive.fetch("maximumSegmentNauticalMiles"))
      unless maximum_segment_nm.finite? && maximum_segment_nm.positive?
        raise SourceError, "Maximum segment length must be finite and positive"
      end
      minimum_segment_nm =
        MAXIMUM_GRID_DIAGONAL_NAUTICAL_MILES_AT_SCALE_ONE.fdiv(scale)
      if maximum_segment_nm < minimum_segment_nm
        raise SourceError,
          "Maximum segment length is smaller than the coordinate grid can represent"
      end
      %w[maximumPathCount maximumCoordinateCount].each do |key|
        raise SourceError, "#{key} must be positive" unless Integer(archive.fetch(key)).positive?
      end
      maximum_bytes = Integer(archive.fetch("maximumOutputBytes"))
      unless maximum_bytes.positive? && maximum_bytes <= MAXIMUM_OUTPUT_BYTES
        raise SourceError, "Maximum output bytes must be from 1 through #{MAXIMUM_OUTPUT_BYTES}"
      end
      validate_expected_output(archive.fetch("expectedOutput")) if archive.key?("expectedOutput")
    end

    def validate_expected_output(expected)
      unless expected.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
        raise SourceError, "Expected output has an invalid SHA-256"
      end
      %w[encodedBytes pathCount coordinateCount].each do |key|
        raise SourceError, "Expected output #{key} must be positive" unless Integer(expected.fetch(key)).positive?
      end
    end

    def validate_sources(sources)
      source_ids = sources.map { |source| source.fetch("id") }
      raise SourceError, "Source IDs must be unique" unless source_ids.uniq.length == source_ids.length
      sources.each do |source|
        %w[id name release scale].each do |key|
          value = source.fetch(key).to_s
          raise SourceError, "Source #{key} must not be empty" if value.strip.empty?
        end
        identifier = source.fetch("id")
        unless identifier.length <= 64 && identifier.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
          raise SourceError, "Source ID #{identifier.inspect} is not lowercase ASCII kebab-case"
        end
      end
      source_ids
    end

    def validate_inputs(inputs, source_ids)
      input_ids = inputs.map { |input| input.fetch("id") }
      raise SourceError, "Input IDs must be unique" unless input_ids.uniq.length == input_ids.length
      inputs.each do |input|
        unless source_ids.include?(input.fetch("sourceID"))
          raise SourceError, "Input #{input.fetch("id")} has an unknown source ID"
        end
        validate_input(input)
        validate_detail_specification(input.fetch("detailLevel"))
      end
    end

    def validate_input(input)
      identifier = input.fetch("id")
      format = input.fetch("format")
      raise SourceError, "Input #{identifier} has an unknown format" unless %w[shapefile geojson].include?(format)
      unless [nil, "shared-edges"].include?(input["boundaryMode"])
        raise SourceError, "Input #{identifier} has an unknown boundary mode"
      end
      deduplication_mode = input.fetch("deduplicationMode", "path")
      unless %w[path segment].include?(deduplication_mode)
        raise SourceError, "Input #{identifier} has an unknown deduplication mode"
      end
      tolerance = Float(input.fetch("simplificationNauticalMiles"))
      unless tolerance.finite? && tolerance >= 0
        raise SourceError, "Input #{identifier} has an invalid simplification tolerance"
      end
      Integer(input.fetch("priority"))
      deduplication_group = input.fetch("deduplicationGroup")
      raise SourceError, "Input #{identifier} has an empty deduplication group" if deduplication_group.empty?
      validate_kind_specification(input.fetch("kind"), identifier)
      validate_archive_specification(input.fetch("archive"), format, identifier)
    end

    def validate_archive_specification(archive, format, identifier)
      %w[file sha256].each { |key| archive.fetch(key) }
      unless archive.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
        raise SourceError, "Input #{identifier} has an invalid SHA-256"
      end
      if format == "shapefile"
        members = archive.fetch("members")
        %w[shp dbf].each { |key| members.fetch(key) }
      elsif archive.key?("members")
        raise SourceError, "GeoJSON input #{identifier} must not declare shapefile members"
      end
    end

    def validate_kind_specification(specification, identifier)
      values = if specification.is_a?(String)
        [specification]
      else
        specification.fetch("property")
        specification.fetch("values", {}).values + [specification.fetch("default")]
      end
      unknown = values.uniq - LINE_KINDS
      return if unknown.empty?

      raise SourceError, "Input #{identifier} has unknown line kind(s): #{unknown.join(", ")}"
    end

    def validate_detail_specification(specification)
      if specification.is_a?(String)
        raise SourceError, "Unknown detail level #{specification}" unless DETAIL_ORDER.key?(specification)
        return
      end

      strategy = specification.fetch("strategy")
      unless %w[natural-earth property numeric-property].include?(strategy)
        raise SourceError, "Unknown detail-level strategy #{strategy}"
      end
      values = case strategy
      when "natural-earth"
        validate_natural_earth_detail(specification)
        DETAIL_ORDER.keys
      when "property"
        specification.fetch("property")
        specification.fetch("values", {}).values + [specification.fetch("default")]
      when "numeric-property"
        validate_numeric_detail(specification)
      end
      unknown = values.uniq - DETAIL_ORDER.keys
      return if unknown.empty?

      raise SourceError, "Unknown detail level(s): #{unknown.join(", ")}"
    end

    def validate_natural_earth_detail(specification)
      %w[minimumZoomProperty scaleRankProperty].each { |key| specification.fetch(key) }
      %w[wide standard].each do |tier|
        thresholds = specification.fetch(tier)
        minimum_zoom = Float(thresholds.fetch("maximumMinimumZoom"))
        scale_rank = Integer(thresholds.fetch("maximumScaleRank"))
        unless minimum_zoom.finite? && minimum_zoom >= 0 && scale_rank >= 0
          raise SourceError, "Natural Earth detail thresholds must be nonnegative"
        end
      end
    end

    def validate_numeric_detail(specification)
      specification.fetch("property")
      values = specification.fetch("rules").map do |rule|
        limits = %w[minimum maximum].filter_map do |key|
          next unless rule.key?(key)

          value = Float(rule.fetch(key))
          raise SourceError, "Numeric detail threshold must be finite" unless value.finite?
          value
        end
        if limits.length == 2 && limits.first > limits.last
          raise SourceError, "Numeric detail minimum must not exceed its maximum"
        end
        rule.fetch("value")
      end
      values + [specification.fetch("default")]
    end
  end
end
