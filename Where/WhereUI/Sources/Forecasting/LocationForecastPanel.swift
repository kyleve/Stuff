import RegionKit
import SwiftUI
import WhereCore

/// Annual location estimates with a soft glass summary on Locations.
/// Locations collapses the summary; calendars and feature discovery show
/// its complete region rows and optional stay-planning controls.
struct LocationForecastPanel: View {
    let forecasts: [LocationForecast]
    let microprintRegions: [Region]
    var homeRegion: Region?
    var planningAction: (() -> Void)?
    var isCollapsible = false

    @State private var isExpanded = false
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
        let showsContent = !isCollapsible || isExpanded

        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if isCollapsible {
                LocationForecastHeader(
                    elapsedDays: forecasts.first?.elapsedDays,
                    isExpanded: showsContent,
                    expansionAction: toggleExpansion,
                )
            } else {
                LocationForecastHeader(
                    elapsedDays: forecasts.first?.elapsedDays,
                    isExpanded: true,
                )
            }

            if showsContent {
                VStack(alignment: .leading, spacing: style.rowSpacing) {
                    ForEach(forecasts, id: \.region) { forecast in
                        LocationForecastRow(
                            forecast: forecast,
                            homeRegion: homeRegion,
                        )
                    }

                    if forecasts.contains(where: { !$0.estimatedTotalDays.isExact }) {
                        Text(String(localized: .forecastDateRangeExplanation))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let planningAction {
                        LocationForecastControls(planningAction: planningAction)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(isCollapsible ? style.summary.padding : style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCollapsible {
                LocationForecastSummarySurface(paths: regionBorderPaths)
            } else {
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
        }
        .overlay {
            if !isCollapsible {
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
        .shadow(
            color: isCollapsible ? .clear : style.surface.shadowColor,
            radius: style.surface.shadowRadius,
            y: style.surface.shadowOffsetY,
        )
        .regionArtworkTask(id: microprintRegions, model: artworkModel, load: loadRegionBorderPaths)
    }

    /// Loads the complete ordered pattern before publishing it so a changing
    /// forecast never shows a partial or stale sequence around the panel.
    private func loadRegionBorderPaths(_ regionOutlinePathCache: RegionOutlinePathCache) async
        -> [Path]?
    {
        var loadedPaths: [Path] = []
        loadedPaths.reserveCapacity(microprintRegions.count)
        for region in microprintRegions {
            let path = await regionOutlinePathCache.path(for: region, resolution: .micro)
            guard !Task.isCancelled else { return nil }
            loadedPaths.append(path)
        }
        return loadedPaths
    }

    private func toggleExpansion() {
        withAnimation(style.expansionAnimation) {
            isExpanded.toggle()
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
    import BroadwayUI
    import SnapshotKit

    extension LocationForecastPanel: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshot(name: "Expanded", collapsible: false, expanded: true)
            snapshot(name: "Collapsed", collapsible: true, expanded: false)
            snapshot(name: "SummaryExpanded", collapsible: true, expanded: true)
            snapshot(
                name: "ReduceTransparency",
                collapsible: true,
                expanded: false,
                reduceTransparency: true,
            )
        }

        private static func snapshot(
            name: String,
            collapsible: Bool,
            expanded: Bool,
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let artwork = RegionArtworkModel<[Region], [Path]>()
            let report = PreviewSupport.plannedStayYearReportModel()
            let regions = report.ranking.primary.map(\.region)
            return whereThemeSnapshot(
                name: name,
                configurations: reduceTransparency ? .componentLightDark : .componentDefaults,
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
                    isCollapsible: collapsible,
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
        LocationForecastPanel.snapshotPreviews
    }
#endif
