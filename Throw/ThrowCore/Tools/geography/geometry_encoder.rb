# frozen_string_literal: true

require_relative "source_archive"

module ThrowGeography
  Candidate = Struct.new(
    :coordinates,
    :kind,
    :detail_level,
    :deduplication_group,
    :input_id,
    keyword_init: true,
  )

  # Simplifies, densifies, quantizes, deduplicates, and encodes source paths.
  class GeometryEncoder
    def initialize(coordinate_scale:, maximum_segment_nautical_miles:, detail_order:)
      minimum_segment_length =
        MAXIMUM_GRID_DIAGONAL_NAUTICAL_MILES_AT_SCALE_ONE.fdiv(coordinate_scale)
      if maximum_segment_nautical_miles < minimum_segment_length
        raise SourceError,
          "Maximum segment length is smaller than the coordinate grid can represent"
      end
      @coordinate_scale = coordinate_scale
      @maximum_segment_nautical_miles = maximum_segment_nautical_miles
      @detail_order = detail_order
      @claimed_paths = Hash.new { |groups, group| groups[group] = {} }
      @claimed_segments = Hash.new { |groups, group| groups[group] = {} }
    end

    def encode(candidate, simplification_nautical_miles:, deduplication_mode: "path")
      simplified = simplify(candidate.coordinates, simplification_nautical_miles)
      return [] if simplified.length < 2

      points = densified_quantized_points(quantized_points(simplified))
      unique_paths = case deduplication_mode
      when "path"
        unique_path(points, candidate.deduplication_group)
      when "segment"
        unique_segments(points, candidate.deduplication_group)
      else
        raise SourceError, "Unknown deduplication mode #{deduplication_mode}"
      end
      unique_paths.filter_map do |unique_points|
        encoded_path(unique_points, candidate.kind, candidate.detail_level)
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
        if adjusted_end == start_longitude
          current << [start_longitude, end_latitude]
          next
        end
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

    # Joins open paths through endpoints that have no branch. Semantic and LOD
    # groups stay separate.
    def merge_connected_candidates(candidates)
      closed, open = candidates.partition do |candidate|
        endpoint_key(candidate.coordinates.first) == endpoint_key(candidate.coordinates.last)
      end
      groups = open.group_by do |candidate|
        [candidate.kind, candidate.detail_level, candidate.deduplication_group, candidate.input_id]
      end
      closed + groups.values.flat_map { |group| merge_candidate_group(group) }
    end

    # Collects polygon rings through the supplied collector and returns only
    # edges that two or more polygons share.
    def shared_boundary_candidates(kind:, deduplication_group:, input_id:)
      edges = {}
      collector = lambda do |paths, detail_level|
        paths.each do |coordinates|
          split_antimeridian(coordinates).each do |path|
            points = quantized_points(path)
            points.each_cons(2) do |first, second|
              next if first == second

              key, ordered = edge_key(first, second)
              entry = edges[key]
              if entry
                entry[:count] += 1
                if @detail_order.fetch(detail_level) < @detail_order.fetch(entry[:detail_level])
                  entry[:detail_level] = detail_level
                end
              else
                edges[key] = { count: 1, points: ordered, detail_level: detail_level }
              end
            end
          end
        end
      end
      yield collector

      by_detail = edges.values.select { |edge| edge.fetch(:count) > 1 }.group_by do |edge|
        edge.fetch(:detail_level)
      end
      by_detail.flat_map do |detail_level, shared_edges|
        merged_edge_paths(shared_edges).map do |points|
          Candidate.new(
            coordinates: points.map do |latitude, longitude|
              [longitude.fdiv(@coordinate_scale), latitude.fdiv(@coordinate_scale)]
            end,
            kind: kind,
            detail_level: detail_level,
            deduplication_group: deduplication_group,
            input_id: input_id,
          )
        end
      end
    end

    private

    def merge_candidate_group(candidates)
      adjacency = Hash.new { |vertices, vertex| vertices[vertex] = [] }
      endpoints = candidates.map do |candidate|
        [endpoint_key(candidate.coordinates.first), endpoint_key(candidate.coordinates.last)]
      end
      endpoints.each_with_index do |(first, last), index|
        adjacency[first] << index
        adjacency[last] << index
      end
      visited = {}
      merged = []
      adjacency.each do |endpoint, indexes|
        next if indexes.length == 2

        indexes.each do |index|
          next if visited[index]

          merged << walk_candidate_paths(endpoint, index, candidates, endpoints, adjacency, visited)
        end
      end
      candidates.each_index do |index|
        next if visited[index]

        merged << walk_candidate_paths(endpoints[index].first, index, candidates, endpoints, adjacency, visited)
      end
      merged
    end

    def walk_candidate_paths(start, first_index, candidates, endpoints, adjacency, visited)
      coordinates = []
      endpoint = start
      index = first_index
      template = candidates[index]
      loop do
        visited[index] = true
        first, last = endpoints[index]
        oriented = first == endpoint ? candidates[index].coordinates : candidates[index].coordinates.reverse
        coordinates.concat(coordinates.empty? ? oriented : oriented.drop(1))
        endpoint = first == endpoint ? last : first
        next_indexes = adjacency[endpoint].reject { |candidate_index| visited[candidate_index] }
        break unless next_indexes.length == 1

        index = next_indexes.first
      end
      Candidate.new(
        coordinates: coordinates,
        kind: template.kind,
        detail_level: template.detail_level,
        deduplication_group: template.deduplication_group,
        input_id: template.input_id,
      )
    end

    def endpoint_key(coordinate)
      longitude, latitude = coordinate
      [(latitude * @coordinate_scale).round, (longitude * @coordinate_scale).round].pack("q<2")
    end

    def unique_path(points, group)
      return [] if points.length < 2

      forward = points.flatten.pack("q<*")
      reverse = points.reverse.flatten.pack("q<*")
      key = forward < reverse ? forward : reverse
      return [] if @claimed_paths[group].key?(key)

      @claimed_paths[group][key] = true
      [points]
    end

    def unique_segments(points, group)
      paths = []
      current = []
      points.each_cons(2) do |first, second|
        next if first == second

        key, = edge_key(first, second)
        if @claimed_segments[group].key?(key)
          paths << current if current.length >= 2
          current = []
          next
        end

        @claimed_segments[group][key] = true
        current = [first] if current.empty?
        current << second
      end
      paths << current if current.length >= 2
      paths
    end

    def edge_key(first, second)
      ordered = first <=> second
      points = ordered <= 0 ? [first, second] : [second, first]
      [points.flatten.pack("q<4"), points]
    end

    def merged_edge_paths(edges)
      edge_points = edges.map { |edge| edge.fetch(:points) }
      adjacency = Hash.new { |vertices, vertex| vertices[vertex] = [] }
      edge_points.each_with_index do |(first, second), index|
        adjacency[first] << index
        adjacency[second] << index
      end
      visited = {}
      paths = []
      adjacency.each do |point, edge_indexes|
        next if edge_indexes.length == 2

        edge_indexes.each do |edge_index|
          next if visited[edge_index]

          paths << walk_edges(point, edge_index, edge_points, adjacency, visited)
        end
      end
      edge_points.each_index do |edge_index|
        next if visited[edge_index]

        paths << walk_edges(edge_points[edge_index].first, edge_index, edge_points, adjacency, visited)
      end
      paths
    end

    def walk_edges(start, first_edge_index, edges, adjacency, visited)
      path = [start]
      point = start
      edge_index = first_edge_index
      loop do
        visited[edge_index] = true
        first, second = edges[edge_index]
        point = first == point ? second : first
        path << point
        candidates = adjacency[point].reject { |candidate| visited[candidate] }
        break unless candidates.length == 1

        edge_index = candidates.first
      end
      path
    end

    def encoded_path(points, kind, detail_level)
      points = points.each_with_object([]) { |point, unique| unique << point if unique.last != point }
      return nil if points.length < 2
      if points.each_cons(2).any? do |first, second|
        quantized_distance_nautical_miles(first, second) > @maximum_segment_nautical_miles
      end
        raise SourceError, "Encoded geography segment exceeds the configured maximum"
      end

      latitudes = points.map(&:first)
      longitudes = points.map(&:last)
      {
        "kind" => kind,
        "detailLevel" => detail_level,
        "bounds" => [latitudes.min, longitudes.min, latitudes.max, longitudes.max],
        "coordinates" => delta_coordinates(points),
      }
    end

    def simplify(coordinates, tolerance_nm)
      return coordinates if coordinates.length <= 2 || tolerance_nm <= 0
      return simplify_closed(coordinates, tolerance_nm) if coordinates.first == coordinates.last

      simplify_open(coordinates, tolerance_nm)
    end

    def simplify_closed(coordinates, tolerance_nm)
      ring = coordinates[0...-1]
      return coordinates if ring.length <= 3

      anchor = ring.first
      split_index = (1...ring.length).max_by { |index| distance_nautical_miles(anchor, ring[index]) }
      first_half = simplify_open(ring[0..split_index], tolerance_nm)
      second_half = simplify_open(ring[split_index..] + [anchor], tolerance_nm)
      simplified = first_half + second_half.drop(1)
      simplified.last == simplified.first ? simplified : simplified + [simplified.first]
    end

    def simplify_open(coordinates, tolerance_nm)
      keep = { 0 => true, coordinates.length - 1 => true }
      stack = [[0, coordinates.length - 1]]
      until stack.empty?
        first_index, last_index = stack.pop
        maximum_distance = -1.0
        maximum_index = nil
        ((first_index + 1)...last_index).each do |index|
          distance = point_segment_distance_nautical_miles(
            coordinates[index],
            coordinates[first_index],
            coordinates[last_index],
          )
          if distance > maximum_distance
            maximum_distance = distance
            maximum_index = index
          end
        end
        next unless maximum_index && maximum_distance > tolerance_nm

        keep[maximum_index] = true
        stack << [first_index, maximum_index]
        stack << [maximum_index, last_index]
      end
      keep.keys.sort.map { |index| coordinates[index] }
    end

    def point_segment_distance_nautical_miles(point, start_point, end_point)
      reference_latitude = (point[1] + start_point[1] + end_point[1]) / 3
      longitude_scale = Math.cos(reference_latitude * Math::PI / 180)
      px = point[0] * longitude_scale * 60
      py = point[1] * 60
      sx = start_point[0] * longitude_scale * 60
      sy = start_point[1] * 60
      ex = end_point[0] * longitude_scale * 60
      ey = end_point[1] * 60
      dx = ex - sx
      dy = ey - sy
      squared_length = dx * dx + dy * dy
      return Math.hypot(px - sx, py - sy) if squared_length.zero?

      fraction = [[((px - sx) * dx + (py - sy) * dy) / squared_length, 0].max, 1].min
      Math.hypot(px - (sx + fraction * dx), py - (sy + fraction * dy))
    end

    def densified_quantized_points(points)
      result = [points.first]
      points.each_cons(2) do |start_point, end_point|
        segment_count = [
          (quantized_distance_nautical_miles(start_point, end_point) /
            @maximum_segment_nautical_miles).ceil,
          1,
        ].max
        loop do
          samples = (1..segment_count).map do |index|
            fraction = index.fdiv(segment_count)
            [
              (start_point[0] + (end_point[0] - start_point[0]) * fraction).round,
              (start_point[1] + (end_point[1] - start_point[1]) * fraction).round,
            ]
          end
          samples = samples.each_with_object([]) do |point, unique|
            unique << point if unique.last != point
          end
          candidate_points = [result.last] + samples
          if candidate_points.each_cons(2).all? do |first, second|
            quantized_distance_nautical_miles(first, second) <=
              @maximum_segment_nautical_miles
          end
            result.concat(samples)
            break
          end
          segment_count += 1
        end
      end
      result
    end

    def quantized_distance_nautical_miles(start_point, end_point)
      distance_nautical_miles(
        [
          start_point[1].fdiv(@coordinate_scale),
          start_point[0].fdiv(@coordinate_scale),
        ],
        [
          end_point[1].fdiv(@coordinate_scale),
          end_point[0].fdiv(@coordinate_scale),
        ],
      )
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

    def quantized_points(coordinates)
      coordinates.each_with_object([]) do |(longitude, latitude), points|
        point = [(latitude * @coordinate_scale).round, (longitude * @coordinate_scale).round]
        points << point if points.last != point
      end
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
