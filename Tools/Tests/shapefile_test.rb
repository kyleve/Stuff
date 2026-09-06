# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../Throw/ThrowCore/Tools/geography/shapefile"

class GeographyShapefileTest < Minitest::Test
  def test_reads_polyline_parts_and_typed_dbase_properties
    shapefile = shapefile_data(
      [
        [[-122.5, 37.7], [-122.4, 37.8]],
        [[-122.3, 37.9], [-122.2, 38.0]],
      ],
    )
    dbase = dbase_data(
      [{ "CLASS" => "I", "RANK" => "7" }],
      fields: [["CLASS", "C", 4, 0], ["RANK", "N", 3, 0]],
    )

    features = ThrowGeography::ShapefileReader.new(
      shapefile_data: shapefile,
      dbase_data: dbase,
    ).each_feature.to_a

    assert_equal 1, features.length
    assert_equal 2, features.first.paths.length
    assert_equal [-122.5, 37.7], features.first.paths.first.first
    assert_equal({ "CLASS" => "I", "RANK" => 7 }, features.first.properties)
  end

  def test_rejects_a_truncated_shapefile_header
    error = assert_raises(ThrowGeography::SourceError) do
      ThrowGeography::ShapefileReader.new(
        shapefile_data: "short",
        dbase_data: dbase_data([], fields: []),
      ).each_feature.to_a
    end

    assert_includes error.message, "header is truncated"
  end

  def test_rejects_a_truncated_dbase_header
    error = assert_raises(ThrowGeography::SourceError) do
      ThrowGeography::DBaseReader.new("short")
    end

    assert_includes error.message, "DBF header is truncated"
  end

  def test_rejects_a_shapefile_and_dbase_record_count_mismatch
    reader = ThrowGeography::ShapefileReader.new(
      shapefile_data: shapefile_data([[[0.0, 0.0], [1.0, 1.0]]]),
      dbase_data: dbase_data([], fields: [["CLASS", "C", 4, 0]]),
    )

    error = assert_raises(ThrowGeography::SourceError) { reader.each_feature.to_a }

    assert_includes error.message, "more records than its DBF"
  end

  private

  def shapefile_data(paths)
    points = paths.flatten(1)
    longitudes = points.map(&:first)
    latitudes = points.map(&:last)
    bounds = [longitudes.min, latitudes.min, longitudes.max, latitudes.max]
    starts = []
    offset = 0
    paths.each do |path|
      starts << offset
      offset += path.length
    end
    content = [3].pack("V") + bounds.pack("E4") +
      [paths.length, points.length].pack("V2") + starts.pack("V*") + points.flatten.pack("E*")
    record = [1, content.bytesize / 2].pack("N2") + content
    file_length = (100 + record.bytesize) / 2
    [9994, 0, 0, 0, 0, 0, file_length].pack("N7") +
      [1000, 3].pack("V2") + bounds.pack("E4") + [0.0, 0.0, 0.0, 0.0].pack("E4") + record
  end

  def dbase_data(rows, fields:)
    header_length = 32 + fields.length * 32 + 1
    record_length = 1 + fields.sum { |field| field.fetch(2) }
    header = [3, 0, 0, 0].pack("C4") + [rows.length].pack("V") +
      [header_length, record_length].pack("v2") + ("\0" * 20)
    descriptors = fields.map do |name, type, length, decimal_count|
      name.ljust(11, "\0") + type + ("\0" * 4) +
        [length, decimal_count].pack("C2") + ("\0" * 14)
    end.join
    records = rows.map do |row|
      " " + fields.map do |name, _type, length, _decimal_count|
        row.fetch(name).to_s.rjust(length)
      end.join
    end.join
    header + descriptors + "\r" + records + "\x1A"
  end
end
