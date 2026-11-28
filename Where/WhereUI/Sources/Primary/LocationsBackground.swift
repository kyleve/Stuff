import BroadwayUI
import RegionKit
import SwiftUI

/// Stationary, noninteractive paper texture for the selected year's visited regions.
struct LocationsBackground: View {
    let regions: [Region]

    @Environment(\.stylesheet) private var stylesheet
    @State private var artworkModel = RegionArtworkModel<[Region], LocationsBackgroundArtwork>()

    private var style: WhereStylesheet.LocationsBackgroundStyle {
        stylesheet.locationsBackground
    }

    private var requestedRegions: [Region] {
        style.showsInk ? regions.filter { $0 != .other } : []
    }

    var body: some View {
        ZStack {
            style.paper
            if style.showsInk {
                SecurityPrintRosette(
                    tint: style.ink,
                    wobble: style.rosette.wobble,
                    lineWidth: style.rosette.lineWidth,
                    primaryRingSpacing: style.rosette.primaryRingSpacing,
                    secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                    primaryOpacity: style.rosetteOpacity,
                    secondaryOpacity: style.rosetteOpacity,
                )

                VisitedRegionSilhouettes(
                    artworkModel: artworkModel,
                    requestedRegions: requestedRegions,
                    style: style,
                )
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .regionArtworkTask(id: requestedRegions, model: artworkModel) { cache in
            await LocationsBackgroundArtwork.load(regions: requestedRegions, cache: cache)
        }
    }
}

extension View {
    func visitedRegionsBackground(_ report: YearReportModel) -> some View {
        background {
            LocationsBackground(regions: LocationsBackgroundArtwork.regions(in: report.ranking))
                .ignoresSafeArea()
        }
    }
}

#if DEBUG
    import SnapshotKit

    extension LocationsBackground: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            artworkSnapshot(name: "Empty", regions: [])
            artworkSnapshot(name: "One", regions: [.california])
            artworkSnapshot(name: "Several", regions: [.california, .newYork, .ontario, .other])
            artworkSnapshot(name: "Many", regions: Array(Region.allCases.prefix(40)))
            artworkSnapshot(
                name: "ReduceTransparency",
                regions: [.ontario, .other],
                reduceTransparency: true,
            )
        }

        private static func artworkSnapshot(
            name: String,
            regions: [Region],
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = PreviewSupport.snapshotArtworkCache
            return whereSnapshot(
                name: name,
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                prepareForCapture: {
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
