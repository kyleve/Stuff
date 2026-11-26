# frozen_string_literal: true

# TWKB 2D MultiPolygon at seven decimal places, the precision of the normalized source.
module TinyWKB
  def self.encode(geometry)
    polygons = geometry.fetch("coordinates")
    polygons = [polygons] if geometry.fetch("type") == "Polygon"
    output = [0xE6, 0].pack("C*")
    append_unsigned = lambda do |value|
      while value >= 128
        output << ((value & 127) | 128)
        value >>= 7
      end
      output << value
    end
    append_unsigned.call(polygons.length)
    x = y = 0
    polygons.each do |rings|
      append_unsigned.call(rings.length)
      rings.each do |ring|
        raise "Invalid polygon ring" unless ring.length >= 4 && ring.first == ring.last
        append_unsigned.call(ring.length - 1)
        ring.length.pred.times do |i|
          lon, lat = ring.fetch(i)
          nx, ny = (lon * 10_000_000).round, (lat * 10_000_000).round
          unless lon.between?(-180, 180) && lat.between?(-90, 90) &&
                 (nx / 10_000_000.0 - lon).abs < 1e-12 && (ny / 10_000_000.0 - lat).abs < 1e-12
            raise "Geometry exceeds the pinned precision or WGS84 bounds"
          end
          dx, dy = nx - x, ny - y
          append_unsigned.call((dx << 1) ^ (dx >> 63))
          append_unsigned.call((dy << 1) ^ (dy >> 63))
          x, y = nx, ny
        end
      end
    end
    output
  end
end
