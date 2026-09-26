import RegionKit
import SwiftUI

/// Cached outlines retain their membership so obsolete loads cannot decorate a new year.
struct LocationsBackgroundArtwork {
    struct Item: Identifiable {
        let region: Region
        let path: Path

        var id: Region {
            region
        }
    }

    let items: [Item]

    static func regions(in ranking: RegionRanking) -> [Region] {
        let visited = Set((ranking.primary + ranking.secondary).map(\.region))
        return Region.allCases.filter { visited.contains($0) }
    }

    func items(for regions: [Region]) -> [Item] {
        items.map(\.region) == regions ? items : []
    }

    static func load(regions: [Region], cache: RegionOutlinePathCache) async -> Self? {
        var items: [Item] = []
        for region in regions {
            guard !Task.isCancelled else { return nil }
            let path = await cache.path(for: region, resolution: .small)
            items.append(Item(region: region, path: path))
        }
        guard !Task.isCancelled else { return nil }
        return Self(items: items)
    }
}
