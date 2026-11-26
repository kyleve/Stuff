import Foundation

/// Reads the normalized 2D MultiPolygon representation written by the maintainer tool.
/// TWKB stores rings with implicit closure and coordinates as scaled integer deltas.
enum TinyWKB {
    static func polygons(in data: Data) throws -> [GeoPolygon] {
        try data.withUnsafeBytes { bytes in
            var reader = Reader(bytes: bytes)
            return try reader.polygons()
        }
    }

    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var offset = 0
        var longitude = 0
        var latitude = 0

        mutating func polygons() throws -> [GeoPolygon] {
            guard bytes.count >= 3, bytes[0] == 0xE6,
                  bytes[1] == 0 else { throw CocoaError(.fileReadCorruptFile) }
            offset = 2
            let count = try unsigned()
            guard count > 0,
                  count <= (bytes.count - offset) / 8
            else { throw CocoaError(.fileReadCorruptFile) }
            var polygons: [GeoPolygon] = []
            polygons.reserveCapacity(count)
            for _ in 0 ..< count {
                let ringCount = try unsigned()
                guard ringCount > 0,
                      ringCount <= (bytes.count - offset) / 7
                else { throw CocoaError(.fileReadCorruptFile) }
                let exterior = try ring()
                var holes: [[Coordinate]] = []
                for _ in 1 ..< ringCount {
                    try holes.append(ring())
                }
                polygons.append(GeoPolygon(vertices: exterior, holes: holes))
            }
            guard offset == bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            return polygons
        }

        mutating func ring() throws -> [Coordinate] {
            let count = try unsigned()
            guard count >= 3,
                  count <= (bytes.count - offset) / 2
            else { throw CocoaError(.fileReadCorruptFile) }
            var ring: [Coordinate] = []
            ring.reserveCapacity(count + 1)
            for _ in 0 ..< count {
                let x = try unsigned(), y = try unsigned()
                longitude += (x >> 1) ^ -(x & 1)
                latitude += (y >> 1) ^ -(y & 1)
                guard abs(longitude) <= 1_800_000_000,
                      abs(latitude) <= 900_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                ring.append(Coordinate(
                    latitude: Double(latitude) / 10_000_000,
                    longitude: Double(longitude) / 10_000_000,
                ))
            }
            ring.append(ring[0])
            return ring
        }

        mutating func unsigned() throws -> Int {
            var value = 0
            var shift = 0
            while offset < bytes.count, shift <= 28 {
                let byte = Int(bytes[offset])
                offset += 1
                value |= (byte & 127) << shift
                if byte < 128 { return value }
                shift += 7
            }
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
