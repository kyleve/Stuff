import RegionKit
import SwiftUI

struct VisitedRegionSilhouettes: View {
    let artworkModel: RegionArtworkModel<[Region], LocationsBackgroundArtwork>
    let requestedRegions: [Region]
    let style: WhereStylesheet.LocationsBackgroundStyle

    var body: some View {
        GeometryReader { proxy in
            let items = artworkModel.artwork(for: requestedRegions)?
                .items(for: requestedRegions) ?? []
            let cells = LocationsBackgroundLayout.cells(
                count: items.count,
                in: proxy.size,
                preferredCellSize: style.preferredCellSize,
            )
            ZStack(alignment: .topLeading) {
                ForEach(cells) { cell in
                    let item = items[cell.artworkIndex]
                    RegionOutlineArtwork(
                        path: item.path,
                        tint: style.ink,
                        style: balancedArtwork(for: item.path),
                    )
                    .frame(width: cell.frame.width, height: cell.frame.height)
                    .position(x: cell.frame.midX, y: cell.frame.midY)
                }
            }
        }
    }

    private func balancedArtwork(for path: Path) -> WhereStylesheet.CardStyle.RegionShape.Artwork {
        var artwork = style.artwork
        let bounds = path.boundingRect
        let shortSide = min(bounds.width, bounds.height)
        guard shortSide > 0 else { return artwork }
        // Give slender regions more room without changing the shared geographic projection.
        artwork.scale *= min(
            style.maximumAspectScale,
            sqrt(max(bounds.width, bounds.height) / shortSide),
        )
        return artwork
    }
}

#if DEBUG
    #Preview("Visited locations") {
        LocationsBackground(regions: [.california, .newYork, .ontario])
            .whereBroadwayRoot()
    }
#endif
