# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../Throw/ThrowCore/Tools/geography/geometry_encoder"

class GeographyGeometryEncoderTest < Minitest::Test
  DETAIL_ORDER = { "wide" => 0, "standard" => 1, "local" => 2 }.freeze

  def setup
    @encoder = ThrowGeography::GeometryEncoder.new(
      coordinate_scale: 10_000,
      maximum_segment_nautical_miles: 10,
      detail_order: DETAIL_ORDER,
    )
  end

  def test_exact_dateline_alias_does_not_divide_by_zero_or_create_a_world_segment
    paths = @encoder.split_antimeridian([[180.0, 1.0], [-180.0, 2.0]])

    assert_equal [[[180.0, 1.0], [180.0, 2.0]]], paths
  end

  def test_segment_deduplication_removes_a_reversed_duplicate
    first = candidate([[0.0, 0.0], [0.1, 0.0]])
    second = candidate([[0.1, 0.0], [0.0, 0.0]])

    first_paths = @encoder.encode(
      first,
      simplification_nautical_miles: 0,
      deduplication_mode: "segment",
    )
    second_paths = @encoder.encode(
      second,
      simplification_nautical_miles: 0,
      deduplication_mode: "segment",
    )

    assert_equal 1, first_paths.length
    assert_empty second_paths
  end

  def test_shared_boundaries_keep_only_the_common_polygon_edge
    candidates = @encoder.shared_boundary_candidates(
      kind: "regional-boundary",
      deduplication_group: "boundary",
      input_id: "fixture",
    ) do |collector|
      collector.call(
        [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]],
        "local",
      )
      collector.call(
        [[[1.0, 0.0], [2.0, 0.0], [2.0, 1.0], [1.0, 1.0], [1.0, 0.0]]],
        "wide",
      )
    end

    assert_equal 1, candidates.length
    assert_equal [[1.0, 0.0], [1.0, 1.0]], candidates.first.coordinates
    assert_equal "wide", candidates.first.detail_level
  end

  def test_connected_paths_merge_without_crossing_a_branch
    candidates = [
      candidate([[0.0, 0.0], [1.0, 0.0]]),
      candidate([[1.0, 0.0], [2.0, 0.0]]),
      candidate([[2.0, 0.0], [3.0, 0.0]]),
    ]

    merged = @encoder.merge_connected_candidates(candidates)

    assert_equal 1, merged.length
    assert_equal [[0.0, 0.0], [1.0, 0.0], [2.0, 0.0], [3.0, 0.0]], merged.first.coordinates
  end

  def test_quantized_high_latitude_segments_do_not_exceed_the_limit
    paths = @encoder.encode(
      candidate([[0.0, 78.0], [20.0, 78.0]]),
      simplification_nautical_miles: 0,
    )
    points = decoded_points(paths.fetch(0).fetch("coordinates"))

    maximum = points.each_cons(2).map do |first, second|
      distance_nautical_miles(first, second)
    end.max

    assert_operator maximum, :<=, 10
  end

  def test_maximum_manifest_scale_supports_longitude_keys
    encoder = ThrowGeography::GeometryEncoder.new(
      coordinate_scale: 1_000_000_000,
      maximum_segment_nautical_miles: 10,
      detail_order: DETAIL_ORDER,
    )

    paths = encoder.encode(
      candidate([[179.999999, 0.0], [180.0, 0.0]]),
      simplification_nautical_miles: 0,
    )

    assert_equal 1, paths.length
  end

  def test_rejects_a_segment_limit_smaller_than_the_coordinate_grid
    error = assert_raises(ThrowGeography::SourceError) do
      ThrowGeography::GeometryEncoder.new(
        coordinate_scale: 10_000,
        maximum_segment_nautical_miles: 0.001,
        detail_order: DETAIL_ORDER,
      )
    end

    assert_includes error.message, "coordinate grid"
  end

  private

  def candidate(coordinates)
    ThrowGeography::Candidate.new(
      coordinates: coordinates,
      kind: "coastline",
      detail_level: "wide",
      deduplication_group: "fixture",
      input_id: "fixture",
    )
  end

  def decoded_points(values)
    latitude = values.fetch(0)
    longitude = values.fetch(1)
    points = [[longitude.fdiv(10_000), latitude.fdiv(10_000)]]
    values.drop(2).each_slice(2) do |latitude_delta, longitude_delta|
      latitude += latitude_delta
      longitude += longitude_delta
      points << [longitude.fdiv(10_000), latitude.fdiv(10_000)]
    end
    points
  end

  def distance_nautical_miles(start_point, end_point)
    longitude1, latitude1 = start_point.map { |value| value * Math::PI / 180 }
    longitude2, latitude2 = end_point.map { |value| value * Math::PI / 180 }
    delta_latitude = latitude2 - latitude1
    delta_longitude = longitude2 - longitude1
    haversine = Math.sin(delta_latitude / 2)**2 +
      Math.cos(latitude1) * Math.cos(latitude2) * Math.sin(delta_longitude / 2)**2
    3_440.069_546_436_138 * 2 * Math.asin(Math.sqrt([[haversine, 0].max, 1].min))
  end
end
