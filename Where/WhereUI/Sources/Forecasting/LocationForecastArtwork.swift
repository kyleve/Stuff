import RegionKit
import SwiftUI

/// Loads the complete ordered border before publication, without partial or cancelled artwork.
@MainActor
enum LocationForecastArtwork {
    struct Item: Identifiable {
        let region: Region
        let watermark: Path
        let microprint: Path

        var id: Region {
            region
        }
    }

    /// Summary watermarks use medium detail; the inset border keeps micro detail.
    static func loadSummary(regions: [Region], cache: RegionOutlinePathCache) async -> [Item]? {
        var items: [Item] = []
        items.reserveCapacity(regions.count)
        for region in regions {
            guard !Task.isCancelled else { return nil }
            async let watermark = cache.path(for: region, resolution: .medium)
            async let microprint = cache.path(for: region, resolution: .micro)
            let item = await Item(region: region, watermark: watermark, microprint: microprint)
            guard !Task.isCancelled else { return nil }
            items.append(item)
        }
        return items
    }

    static func load(regions: [Region], cache: RegionOutlinePathCache) async -> [Path]? {
        var paths: [Path] = []
        paths.reserveCapacity(regions.count)
        for region in regions {
            let path = await cache.path(for: region, resolution: .micro)
            guard !Task.isCancelled else { return nil }
            paths.append(path)
        }
        return paths
    }
}
