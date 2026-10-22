import RegionKit
import SwiftUI

/// Loads the complete ordered border before publication, without partial or cancelled artwork.
@MainActor
enum LocationForecastArtwork {
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
