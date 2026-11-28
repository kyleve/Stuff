import Foundation
import Synchronization

/// Share immutable coordinate buffers across tracked snapshots and artwork. Each file
/// has its own cold-load lock so a large subdivision cannot block unrelated hits.
enum RegionGeometryReader {
    private final class Entry: Sendable {
        let polygons = Mutex<[GeoPolygon]?>(nil)
    }

    private static let cache = Mutex({
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }())

    static func polygons(at url: URL) throws -> [GeoPolygon] {
        let entry = cache.withLock { cache in
            if let existing = cache.object(forKey: url as NSURL) {
                return existing
            }
            let entry = Entry()
            cache.setObject(entry, forKey: url as NSURL)
            return entry
        }
        return try entry.polygons.withLock { stored in
            if let stored {
                return stored
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let polygons = try url.pathExtension == "twkb"
                ? TinyWKB.polygons(in: data) : GeoJSON.polygons(in: data)
            let bytes = polygons.reduce(0) { total, polygon in
                let coordinates = polygon.vertices.count + polygon.holes.reduce(0) { $0 + $1.count }
                return total + MemoryLayout<GeoPolygon>
                    .stride + coordinates * MemoryLayout<Coordinate>.stride
            }
            stored = polygons
            cache.withLock { $0.setObject(entry, forKey: url as NSURL, cost: bytes) }
            return polygons
        }
    }
}
