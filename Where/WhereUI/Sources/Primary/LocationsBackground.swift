import BroadwayUI
import RegionKit
import SFSafeSymbols
import SwiftUI

/// Stationary, noninteractive paper texture for the root Locations viewport.
struct LocationsBackground: View {
    let regions: [Region]

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionOutlinePathCache) private var cache
    @State private var artwork: LocationsBackgroundArtwork?

    private var style: WhereStylesheet.LocationsBackgroundStyle {
        stylesheet.locationsBackground
    }

    private var requestedRegions: [Region] {
        style.showsInk ? regions : []
    }

    var body: some View {
        ZStack {
            style.paper
            if style.showsInk {
                silhouettes
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: requestedRegions) {
            guard let cache else { return }
            if let loaded = await LocationsBackgroundArtwork.load(
                regions: requestedRegions,
                cache: cache,
            ) {
                guard !Task.isCancelled else { return }
                artwork = loaded
            }
        }
    }

    private var silhouettes: some View {
        GeometryReader { proxy in
            let items = artwork?.items(for: requestedRegions) ?? []
            let cells = LocationsBackgroundLayout.cells(
                count: items.count,
                in: proxy.size,
                preferredCellSize: style.preferredCellSize,
            )
            ZStack(alignment: .topLeading) {
                ForEach(cells) { cell in
                    Group {
                        switch cell.motif {
                            case let .region(index):
                                let item = items[index]
                                if item.region == .other {
                                    Image(systemSymbol: .globeAmericas)
                                        .resizable()
                                        .scaledToFit()
                                        .fontWeight(style.symbolWeight)
                                        .foregroundStyle(style.ink.opacity(style.symbolOpacity))
                                        .padding(cell.frame
                                            .width * (1 - style.artwork.extent.width) / 2)
                                } else {
                                    RegionOutlineArtwork(
                                        path: item.path,
                                        tint: style.ink,
                                        style: balancedArtwork(for: item.path),
                                    )
                                }
                            case .rosette:
                                LocationsMonogramRosette()
                                    .stroke(
                                        style.ink.opacity(style.rosette.opacity),
                                        lineWidth: style.rosette.lineWidth,
                                    )
                                    .padding(cell.frame.width * (1 - style.rosette.extent) / 2)
                        }
                    }
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

/// A compact six-petal seal that anchors the repeating geographic print.
private struct LocationsMonogramRosette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for step in 0 ... 120 {
            let angle = Double(step) / 120 * .pi * 2
            let petalRadius = radius * (0.82 + 0.18 * cos(angle * 6))
            let point = CGPoint(
                x: center.x + cos(angle) * petalRadius,
                y: center.y + sin(angle) * petalRadius,
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        path.addEllipse(in: CGRect(
            x: center.x - radius * 0.28,
            y: center.y - radius * 0.28,
            width: radius * 0.56,
            height: radius * 0.56,
        ))
        return path
    }
}

#if DEBUG
    import SnapshotKit

    extension LocationsBackground: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            artworkSnapshot(name: "Empty", regions: [])
            artworkSnapshot(name: "One", regions: [.california])
            artworkSnapshot(name: "Several", regions: [.california, .newYork, .canada, .other])
            artworkSnapshot(name: "Many", regions: Array(Region.allCases.prefix(40)))
            artworkSnapshot(
                name: "ReduceTransparency",
                regions: [.canada, .other],
                reduceTransparency: true,
            )
        }

        private static func artworkSnapshot(
            name: String,
            regions: [Region],
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            return whereSnapshot(
                name: name,
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                onReadyToSnapshot: {
                    _ = await LocationsBackgroundArtwork.load(regions: regions, cache: cache)
                },
            ) {
                LocationsBackground(regions: regions)
                    .environment(\.regionOutlinePathCache, cache)
                    .bTraitOverrides { traits, overrides in
                        var accessibility = traits.accessibility
                        accessibility.isReduceTransparencyEnabled = reduceTransparency
                        overrides.accessibility = accessibility
                    }
            }
        }
    }

    #Preview {
        LocationsBackground.snapshotPreviews
    }
#endif
