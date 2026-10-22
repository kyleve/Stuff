import RegionKit
import SwiftUI
import WhereCore

/// Always-expanded passport panel for calendars, timelines, and feature discovery.
struct LocationForecastPanel: View {
    let forecasts: [LocationForecast]
    let microprintRegions: [Region]
    var homeRegion: Region?
    var planningAction: (() -> Void)?

    @State private var artworkModel = RegionArtworkModel<[Region], [Path]>()

    private var regionBorderPaths: [Path] {
        artworkModel.artwork(for: microprintRegions) ?? []
    }

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.LocationForecastStyle {
        stylesheet.locationForecast
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        VStack(alignment: .leading, spacing: style.rowSpacing) {
            LocationForecastHeader(elapsedDays: forecasts.first?.elapsedDays, isExpanded: true)
            LocationForecastContent(
                forecasts: forecasts,
                homeRegion: homeRegion,
                planningAction: planningAction,
            )
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(.background)
                if style.ink.surfaceWashOpacity > 0 {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(style.ink.surfaceWashOpacity),
                            .clear,
                            Color.primary.opacity(style.ink.surfaceWashOpacity * 0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                }
                SecurityPrintRosette(
                    tint: .primary,
                    wobble: style.surface.rosetteWobble,
                    lineWidth: style.surface.rosetteLineWidth,
                    primaryRingSpacing: style.surface.primaryRingSpacing,
                    secondaryRingSpacing: style.surface.secondaryRingSpacing,
                    primaryOpacity: style.ink.rosettePrimaryOpacity,
                    secondaryOpacity: style.ink.rosetteSecondaryOpacity,
                )
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .overlay {
            ZStack {
                shape.strokeBorder(
                    Color.primary.opacity(style.ink.surfaceOutlineOpacity),
                    lineWidth: style.surface.outlineWidth,
                )
                RegionOutlineSecurityBorder(
                    paths: regionBorderPaths,
                    tint: .primary,
                    cornerRadius: style.cornerRadius,
                    inset: style.surface.inset,
                    glyphSize: style.surface.microprintGlyphSize,
                    spacing: style.surface.microprintSpacing,
                    opacity: style.ink.microprintOpacity,
                )
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: style.surface.shadowColor,
            radius: style.surface.shadowRadius,
            y: style.surface.shadowOffsetY,
        )
        .regionArtworkTask(id: microprintRegions, model: artworkModel) { cache in
            await LocationForecastArtwork.load(regions: microprintRegions, cache: cache)
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.forecasts.leadingForecasts(report: report.report),
            microprintRegions: report.ranking.primary.map(\.region),
            homeRegion: report.forecasts.planning.homeRegion,
            planningAction: {},
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    import SnapshotKit

    extension LocationForecastPanel: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshot()
        }

        private static func snapshot() -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let artwork = RegionArtworkModel<[Region], [Path]>()
            let report = PreviewSupport.plannedStayYearReportModel()
            let regions = report.ranking.primary.map(\.region)
            return whereThemeSnapshot(
                name: "Expanded",
                configurations: .componentDefaults,
                measurementReadiness: .immediate,
                onReadyToSnapshot: {
                    await artwork.load(for: regions) {
                        var paths: [Path] = []
                        for region in regions {
                            await paths.append(cache.path(for: region, resolution: .micro))
                        }
                        return paths
                    }
                },
            ) {
                let report = PreviewSupport.plannedStayYearReportModel()
                var panel = LocationForecastPanel(
                    forecasts: report.forecasts.leadingForecasts(report: report.report),
                    microprintRegions: regions,
                    homeRegion: report.forecasts.planning.homeRegion,
                    planningAction: {},
                )
                panel._artworkModel = State(initialValue: artwork)
                return panel
                    .environment(\.regionOutlinePathCache, cache)
                    .padding(24)
                    .background(.background)
            }
        }
    }

    #Preview("Themes") {
        LocationForecastPanel.snapshotPreviews
    }
#endif
