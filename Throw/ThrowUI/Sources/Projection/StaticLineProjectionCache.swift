import Foundation
import ThrowCore

/// Retains a bounded least-recently-used set of expensive static line projections.
struct StaticLineProjectionCache {
    private static let capacity = 8

    struct Key: Hashable {
        let layerID: LayerID
        let revision: Date
        let mapCenter: GeoCoordinate
        let viewport: ProjectionViewport
        let calibration: ProjectionCalibration
    }

    private struct Entry {
        let key: Key
        let projection: ProjectedLineCollection
    }

    private var entries: [Entry] = []

    init() {
        entries.reserveCapacity(Self.capacity)
    }

    mutating func projection(for key: Key) -> ProjectedLineCollection? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.projection
    }

    mutating func insert(_ projection: ProjectedLineCollection, for key: Key) {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries.remove(at: index)
        } else if entries.count == Self.capacity {
            entries.removeFirst()
        }
        entries.append(Entry(key: key, projection: projection))
    }
}
