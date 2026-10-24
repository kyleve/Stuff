import Foundation
import ThrowCore

private let staticLineProjectionCacheCapacity = 8

/// Retains a bounded least-recently-used set of expensive static line projections.
struct StaticLineProjectionCache<Layer: ProjectionLineLayerKind> {
    struct Key: Hashable {
        let revision: Date
        let mapCenter: GeoCoordinate
        let viewport: ProjectionViewport
        let calibration: ProjectionCalibration
        let geometry: ProjectionGeometry
    }

    private struct Entry {
        let key: Key
        let frame: ProjectedLayerFrame<Layer>
    }

    private var entries: [Entry] = []

    init() {
        entries.reserveCapacity(staticLineProjectionCacheCapacity)
    }

    mutating func frame(for key: Key) -> ProjectedLayerFrame<Layer>? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.frame
    }

    mutating func insert(_ frame: ProjectedLayerFrame<Layer>, for key: Key) {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries.remove(at: index)
        } else if entries.count == staticLineProjectionCacheCapacity {
            entries.removeFirst()
        }
        entries.append(Entry(key: key, frame: frame))
    }
}
