import RegionKit
import SwiftUI
import WhereCore

/// Locations-only summary that owns expansion and keeps its soft surface in both states.
struct LocationForecastSummary: View {
    let forecasts: [LocationForecast]
    let primaryRegions: [Region]
    var homeRegion: Region?
    var planningAction: (() -> Void)?

    @State private var isExpanded = false
    @State private var artworkModel = RegionArtworkModel<[Region], [LocationForecastArtwork.Item]>()
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            LocationForecastHeader(
                elapsedDays: forecasts.first?.elapsedDays,
                isExpanded: isExpanded,
                expansionAction: toggleExpansion,
            )
            if isExpanded {
                LocationForecastContent(
                    forecasts: forecasts,
                    homeRegion: homeRegion,
                    planningAction: planningAction,
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(style.summary.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LocationForecastSummarySurface(artwork: artworkModel
                .artwork(for: primaryRegions) ?? [])
        }
        .regionArtworkTask(id: primaryRegions, model: artworkModel) { cache in
            await LocationForecastArtwork.loadSummary(regions: primaryRegions, cache: cache)
        }
    }

    private func toggleExpansion() {
        withAnimation(stylesheet.locationForecast.expansionAnimation) {
            isExpanded.toggle()
        }
    }
}

#if DEBUG
    import BroadwayUI
    import SnapshotKit

    extension LocationForecastSummary: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshot(name: "Collapsed", expanded: false)
            snapshot(name: "SummaryExpanded", expanded: true)
            snapshot(
                name: "ReduceTransparency",
                expanded: false,
                reduceTransparency: true,
            )
        }

        private static func snapshot(
            name: String,
            expanded: Bool,
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let artwork = RegionArtworkModel<[Region], [LocationForecastArtwork.Item]>()
            let report = PreviewSupport.plannedStayYearReportModel()
            let regions = report.ranking.primary.map(\.region)
            return whereThemeSnapshot(
                name: name,
                configurations: reduceTransparency ? .componentLightDark : .componentDefaults,
                measurementReadiness: .immediate,
                onReadyToSnapshot: {
                    await artwork.load(for: regions) {
                        await LocationForecastArtwork.loadSummary(regions: regions, cache: cache)
                    }
                },
            ) {
                let report = PreviewSupport.plannedStayYearReportModel()
                var panel = LocationForecastSummary(
                    forecasts: report.forecasts.leadingForecasts(report: report.report),
                    primaryRegions: regions,
                    homeRegion: report.forecasts.planning.homeRegion,
                    planningAction: {},
                )
                panel._isExpanded = State(initialValue: expanded)
                panel._artworkModel = State(initialValue: artwork)
                return panel
                    .environment(\.regionOutlinePathCache, cache)
                    .bTraitOverrides { traits, overrides in
                        if reduceTransparency {
                            var accessibility = traits.accessibility
                            accessibility.isReduceTransparencyEnabled = true
                            overrides.accessibility = accessibility
                        }
                    }
                    .padding(24)
                    .background(.background)
            }
        }
    }

    #Preview("Themes") {
        LocationForecastSummary.snapshotPreviews
    }
#endif
