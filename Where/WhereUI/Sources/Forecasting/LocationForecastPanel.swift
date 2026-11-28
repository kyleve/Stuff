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
            ForecastPanelPaper(style: style)
        }
        .overlay {
            ForecastPanelBorder(style: style, regionBorderPaths: regionBorderPaths)
        }
        .shadow(
            color: style.surface.shadowColor,
            radius: style.surface.shadowRadius,
            y: style.surface.shadowOffsetY,
        )
        .regionArtworkTask(id: microprintRegions, model: artworkModel) { cache in
            await LocationForecastArtworkLoader.load(regions: microprintRegions, cache: cache)
        }
    }
}

private struct ForecastPanelBorder: View {
    let style: WhereStylesheet.LocationForecastStyle
    let regionBorderPaths: [Path]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
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
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.primaryRegionForecasts,
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
            let cache = PreviewSupport.snapshotArtworkCache
            let artwork = RegionArtworkModel<[Region], [Path]>()
            let report = PreviewSupport.plannedStayYearReportModel()
            let regions = report.ranking.primary.map(\.region)
            return whereThemeSnapshot(
                name: "Expanded",
                configurations: .componentRepresentative,
                measurementReadiness: .immediate,
                prepareForCapture: {
                    await artwork.load(for: regions) {
                        await LocationForecastArtworkLoader.load(regions: regions, cache: cache)
                    }
                },
            ) {
                let report = PreviewSupport.plannedStayYearReportModel()
                var panel = LocationForecastPanel(
                    forecasts: report.primaryRegionForecasts,
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
