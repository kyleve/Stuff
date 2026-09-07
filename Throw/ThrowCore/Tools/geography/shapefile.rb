# frozen_string_literal: true

require_relative "source_archive"

module ThrowGeography
  # Reads the PolyLine and Polygon records used by the pinned geography inputs.
  class ShapefileReader
    Feature = Struct.new(:properties, :paths, keyword_init: true)
    SUPPORTED_SHAPE_TYPES = [3, 5, 13, 15, 23, 25].freeze

    def initialize(shapefile_data:, dbase_data:)
      @shapefile_data = shapefile_data
      @dbase_rows = DBaseReader.new(dbase_data).rows
    end

    def each_feature
      return enum_for(__method__) unless block_given?

      validate_header
      record_index = 0
      each_shape_record do |paths|
        properties = @dbase_rows[record_index]
        raise SourceError, "Shapefile has more records than its DBF" if record_index >= @dbase_rows.length

        yield Feature.new(properties: properties, paths: paths) if paths && properties
        record_index += 1
      end
      return if record_index == @dbase_rows.length

      raise SourceError,
        "Shapefile has #{record_index} records but DBF has #{@dbase_rows.length} records"
    end

    private

    def validate_header
      raise SourceError, "Shapefile header is truncated" if @shapefile_data.bytesize < 100
      raise SourceError, "Shapefile magic number is invalid" unless big_u32(@shapefile_data, 0) == 9994
      raise SourceError, "Shapefile version is unsupported" unless little_u32(@shapefile_data, 28) == 1000

      shape_type = little_u32(@shapefile_data, 32)
      return if SUPPORTED_SHAPE_TYPES.include?(shape_type)

      raise SourceError, "Unsupported shapefile type #{shape_type}"
    end

    def each_shape_record
      offset = 100
      while offset < @shapefile_data.bytesize
        raise SourceError, "Shapefile record header is truncated" if offset + 8 > @shapefile_data.bytesize

        content_bytes = big_u32(@shapefile_data, offset + 4) * 2
        offset += 8
        record = @shapefile_data.byteslice(offset, content_bytes)
        raise SourceError, "Shapefile record is truncated" unless record&.bytesize == content_bytes

        yield paths_from(record)
        offset += content_bytes
      end
    end

    def paths_from(record)
      raise SourceError, "Shapefile record has no type" if record.bytesize < 4

      shape_type = little_u32(record, 0)
      return nil if shape_type.zero?
      raise SourceError, "Unsupported shapefile record type #{shape_type}" unless SUPPORTED_SHAPE_TYPES.include?(shape_type)
      raise SourceError, "Shapefile geometry is truncated" if record.bytesize < 44

      part_count = little_u32(record, 36)
      point_count = little_u32(record, 40)
      parts_offset = 44
      points_offset = parts_offset + part_count * 4
      required_bytes = points_offset + point_count * 16
      raise SourceError, "Shapefile geometry is truncated" if record.bytesize < required_bytes
      raise SourceError, "Shapefile geometry has no parts" if part_count.zero?

      starts = part_count.times.map { |index| little_u32(record, parts_offset + index * 4) }
      unless starts.first == 0 && starts.each_cons(2).all? { |first, second| first < second } &&
          starts.last < point_count
        raise SourceError, "Shapefile part indexes are invalid"
      end

      points = point_count.times.map do |index|
        point_offset = points_offset + index * 16
        longitude = little_f64(record, point_offset)
        latitude = little_f64(record, point_offset + 8)
        unless longitude.finite? && latitude.finite? && (-180..180).cover?(longitude) &&
            (-90..90).cover?(latitude)
          raise SourceError, "Shapefile coordinate is outside WGS84 bounds"
        end
        [longitude, latitude]
      end
      starts.each_with_index.map do |start, index|
        finish = index + 1 < starts.length ? starts[index + 1] : points.length
        points[start...finish]
      end
    end

    def big_u32(data, offset)
      data.byteslice(offset, 4).unpack1("N")
    end

    def little_u32(data, offset)
      data.byteslice(offset, 4).unpack1("V")
    end

    def little_f64(data, offset)
      data.byteslice(offset, 8).unpack1("E")
    end
  end

  # Reads dBASE III property rows that align with shapefile records.
  class DBaseReader
    Field = Struct.new(:name, :type, :offset, :length, :decimal_count, keyword_init: true)

    attr_reader :rows

    def initialize(data)
      @data = data
      @rows = read_rows
    end

    private

    def read_rows
      raise SourceError, "DBF header is truncated" if @data.bytesize < 33

      record_count = little_u32(4)
      header_length = little_u16(8)
      record_length = little_u16(10)
      fields = read_fields(header_length)
      required_bytes = header_length + record_count * record_length
      raise SourceError, "DBF records are truncated" if @data.bytesize < required_bytes

      record_count.times.map do |index|
        record = @data.byteslice(header_length + index * record_length, record_length)
        next if record.getbyte(0) == "*".ord
        raise SourceError, "DBF deletion marker is invalid" unless record.getbyte(0) == " ".ord

        fields.to_h do |field|
          raw = record.byteslice(field.offset, field.length).delete("\0").strip
          [field.name, field_value(field, raw)]
        end
      end
    end

    def read_fields(header_length)
      raise SourceError, "DBF header length is invalid" unless header_length >= 33

      fields = []
      offset = 32
      value_offset = 1
      while offset < header_length - 1
        descriptor = @data.byteslice(offset, 32)
        raise SourceError, "DBF field descriptor is truncated" unless descriptor&.bytesize == 32
        break if descriptor.getbyte(0) == 0x0D

        length = descriptor.getbyte(16)
        fields << Field.new(
          name: descriptor.byteslice(0, 11).delete("\0 "),
          type: descriptor.byteslice(11, 1),
          offset: value_offset,
          length: length,
          decimal_count: descriptor.getbyte(17),
        )
        value_offset += length
        offset += 32
      end
      fields
    end

    def field_value(field, raw)
      return nil if raw.empty?
      return nil if %w[N F].include?(field.type) && raw.match?(/\A\*+\z/)

      case field.type
      when "N", "F"
        number = Float(raw)
        field.decimal_count.zero? && number.to_i == number ? number.to_i : number
      when "L"
        %w[Y y T t].include?(raw)
      else
        raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      end
    rescue ArgumentError
      raise SourceError, "DBF field #{field.name} has invalid #{field.type} data"
    end

    def little_u16(offset)
      @data.byteslice(offset, 2).unpack1("v")
    end

    def little_u32(offset)
      @data.byteslice(offset, 4).unpack1("V")
    end
  end
end
