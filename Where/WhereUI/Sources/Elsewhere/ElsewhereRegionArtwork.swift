import RegionKit
import SwiftUI

/// A complete ordered set of cached outlines. The identity travels with the
/// paths so an older load can never decorate a different set of regions.
struct ElsewhereRegionArtwork {
    struct Item: Identifiable {
        let region: Region
        let watermark: Path
        let microprint: Path

        var id: Region {
            region
        }
    }

    let items: [Item]

    var regions: [Region] {
        items.map(\.region)
    }

    func items(for regions: [Region]) -> [Item] {
        self.regions == regions ? items : []
    }

    static func load(
        regions: [Region],
        cache: RegionOutlinePathCache,
    ) async -> Self? {
        var items: [Item] = []
        for region in regions {
            guard !Task.isCancelled else { return nil }
            async let watermark = cache.path(for: region, resolution: .medium)
            async let microprint = cache.path(for: region, resolution: .micro)
            let item = await Item(region: region, watermark: watermark, microprint: microprint)
            items.append(item)
        }
        guard !Task.isCancelled else { return nil }
        return Self(items: items)
    }
}
