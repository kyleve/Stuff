import BroadwayUI
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Locations tab: configured primary regions with recorded days in the selected
/// year, ranked by day count, plus planning and data-resolution actions.
struct LocationsView: View {
    let report: YearReportModel
    var openElsewhere: (() -> Void)?

    @State private var showingResolution = false
    @State private var planningDestination: PlannedStaysDestination?
    @State private var isCardSurfaceVisible = false
    @State private var cardPresentation: LocationCardsPresentationModel

    /// Drives the region cards' tilt-reactive light sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Pairs a tapped card with its pushed calendar so the navigation uses a
    /// matched-geometry zoom (the card expands into the calendar) rather than a
    /// plain slide.
    @Namespace private var calendarTransition

    @Environment(\.stylesheet.card.regular.surface) private var cardSurface

    private var isCardSurfaceUncovered: Bool {
        isCardSurfaceVisible
            && !showingResolution
            && planningDestination == nil
    }

    init(report: YearReportModel, openElsewhere: (() -> Void)? = nil) {
        self.report = report
        self.openElsewhere = openElsewhere
        _cardPresentation = State(initialValue: LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        NavigationStack {
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    LocationsBackground(regions: backgroundRegions)
                        .whereThemeOverlay(.locationsBackground)
                        .ignoresSafeArea()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // Pending reviews remain accessible without increasing
                        // the actionable issue badge.
                        if report.dataIssueCount > 0 || report.hasCorrectionReviews {
                            Button {
                                showingResolution = true
                            } label: {
                                ResolveToolbarLabel(count: report.dataIssueCount)
                            }
                            .accessibilityIdentifier("where_resolution_button")
                        }

                        if showsPlanningMenu {
                            Button(
                                String(localized: .plannedStaysTitle),
                                systemSymbol: .calendarBadgeClock,
                            ) {
                                planningDestination = .list
                            }
                            .accessibilityIdentifier("where_planning_menu")
                        }
                    }
                }
        }
        .environment(\.whereThemeLayersAreActive, isCardSurfaceUncovered)
        .observesTilt(
            tilt,
            enabled: isCardSurfaceUncovered && cardSurface.usesReflection,
        )
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
        }
        .sheet(item: $planningDestination) { destination in
            PlannedStaysDestinationView(destination: destination, report: report)
        }
        // Log View Mode: reveal an inspect badge for the year-report events
        // backing this screen. A no-op in release.
        .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil, .failed:
                LocationsStateView(
                    report: report,
                    planningAction: openPlanning,
                    openElsewhere: openElsewhere,
                )
            case .idle, .loaded, .loading:
                if report.locationRegions.isEmpty {
                    LocationsStateView(
                        report: report,
                        planningAction: openPlanning,
                        openElsewhere: openElsewhere,
                    )
                } else {
                    LocationsCardsView(
                        report: report,
                        cardPresentation: cardPresentation,
                        tilt: tilt,
                        calendarTransition: calendarTransition,
                        isCardSurfaceUncovered: isCardSurfaceUncovered,
                        isCardSurfaceVisible: $isCardSurfaceVisible,
                        planningAction: openPlanning,
                    )
                }
        }
    }

    private var backgroundRegions: [Region] {
        switch report.loadState {
            case .failed:
                []
            case .idle, .loaded, .loading:
                LocationsBackgroundArtwork.regions(in: report.ranking)
        }
    }

    private var showsPlanningMenu: Bool {
        report.showsEstimatedTimeAndPlanning
    }

    private func openPlanning() {
        planningDestination = .list
    }
}

/// The Locations toolbar's Resolve affordance: the checklist icon with a count
/// badge for actionable issues. Pending reviews keep the unbadged icon available.
private struct ResolveToolbarLabel: View {
    let count: Int

    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        Image(systemSymbol: .checklist)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, spacing.xSmall)
                        .padding(.vertical, spacing.xxSmall)
                        .background(.red, in: Capsule())
                        .offset(x: spacing.small, y: -spacing.small)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(String(localized: .tabResolution))
            .accessibilityValue(count > 0 ? Text(count, format: .number) : Text(""))
    }
}

#if DEBUG
    extension LocationsView: SnapshotProviding {
        /// Allow native glass adaptation and the background artwork to settle before capture.
        static var snapshots: [SnapshotCase] {
            for theme in WhereTheme.allCases where theme != .standard {
                artworkSnapshot(
                    name: "\(theme.snapshotReferenceGroup!.rawValue.capitalized)Loaded",
                    report: PreviewSupport.loadedYearReportModel(),
                    configurations: .fullContentScreenRepresentative,
                    theme: theme,
                )
                artworkSnapshot(
                    name: "\(theme.snapshotReferenceGroup!.rawValue.capitalized)ReduceTransparency",
                    report: PreviewSupport.loadedYearReportModel(),
                    configurations: .fullContentPhoneLightDark,
                    theme: theme,
                    reduceTransparency: true,
                )
            }
            artworkSnapshot(
                name: "Itinerary",
                report: PreviewSupport.itineraryYearReportModel(),
                configurations: .fullContentPhoneLightDark,
            )
            artworkSnapshot(
                name: "Loaded",
                report: PreviewSupport.loadedYearReportModel(),
                configurations: .fullContentScreenRepresentative,
            )
            for state in [FlightReviewPreviewState.flightLikely, .stale, .ready, .completed] {
                artworkSnapshot(
                    name: "Flight-" + state.rawValue,
                    report: PreviewSupport.flightYearReportModel(state: state),
                    configurations: .fullContentPhoneLightDark,
                )
            }
            whereSnapshot(
                name: "PlannedStay",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(report: PreviewSupport.plannedStayYearReportModel())
            }
            whereSnapshot(
                name: "ForecastsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(report: forecastsHiddenReport())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(report: PreviewSupport.emptyYearReportModel())
            }
            whereSnapshot(
                name: "MissingDays",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(report: PreviewSupport.missingDaysYearReportModel())
            }
            whereSnapshot(
                name: "ElsewhereOnly",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(
                    report: PreviewSupport.elsewhereOnlyYearReportModel(),
                    openElsewhere: {},
                )
            }
            whereSnapshot(
                name: "ElsewhereWithHome",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                let report = PreviewSupport.elsewhereOnlyYearReportModel()
                report.forecasts.setPlanning(PlanningSnapshot(stays: [], homeRegion: .california))
                return LocationsView(report: report, openElsewhere: {})
            }
            whereSnapshot(
                name: "DotsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(
                    report: PreviewSupport.loadedYearReportModelWithLocationDotsHidden(),
                )
            }
            // Multiple primary cards retain tablet baseline and large-type layout coverage.
            artworkSnapshot(
                name: "ThreePrimaryRegions",
                report: PreviewSupport.multiplePrimaryYearReportModel(),
                configurations: .fullContentPhoneLightDark + [
                    .init(device: .iPadFullContent),
                    .init(dynamicType: .accessibility5, device: .iPadFullContent),
                ],
            )
        }

        private static func artworkSnapshot(
            name: String,
            report: YearReportModel,
            configurations: [SnapshotConfiguration],
            theme: WhereTheme = .standard,
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let regions = LocationsBackgroundArtwork.regions(in: report.ranking)
            return whereSnapshot(
                name: name,
                configurations: configurations,
                theme: theme,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
                onReadyToSnapshot: {
                    // Keep geometry ready across the accessibility renderer's reparenting.
                    // Pixel stability alone can settle on the unloaded symbol fallback.
                    for region in regions {
                        _ = await cache.path(for: region, resolution: .small)
                        _ = await cache.path(for: region, resolution: .medium)
                        _ = await cache.path(for: region, resolution: .micro)
                    }
                },
            ) {
                LocationsView(report: report)
                    .environment(\.regionOutlinePathCache, cache)
                    .bTraitOverrides { traits, overrides in
                        if reduceTransparency {
                            var accessibility = traits.accessibility
                            accessibility.isReduceTransparencyEnabled = true
                            overrides.accessibility = accessibility
                        }
                    }
            }
        }

        private static func forecastsHiddenReport() -> YearReportModel {
            PreviewSupport.loadedYearReportModelWithEstimatedTimeHidden()
        }
    }

    #Preview {
        LocationsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension LocationsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(
            LocationsView.self,
            routes: [
                .push(to: CalendarContentView.flyoverID),
                .modal(to: ResolutionView.flyoverID),
                .modal(to: PlannedStaysView.flyoverID),
                .modal(to: PlannedStayEditor.flyoverID),
            ],
        ) { id, world in
            let state = WhereFlyoverLocationsState(report: world.report)
            return .init(
                id: id,
                title: "Locations",
                navigationContainer: .none,
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "demo",
                        title: "Demo data",
                        world: world,
                    ) {
                        LocationsView(report: state.report)
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "empty",
                        title: "Empty",
                        world: world,
                    ) {
                        LocationsView(report: PreviewSupport.emptyYearReportModel())
                    },
                ],
                reset: state.reset,
            ) {
                WhereFlyoverLocationsControls(state: state)
            }
        }
    }
#endif

#if DEBUG
    extension LocationsView {
        @MainActor
        enum SeasonalThemes: SnapshotProviding {
            static var snapshots: [SnapshotCase] {
                for example in WhereThemeExamples.allCases {
                    snapshot(example)
                }
            }

            private static func snapshot(_ example: WhereThemeExamples) -> SnapshotCase {
                let theme: PreparedWhereThemeDocument
                do { theme = try example.prepare() }
                catch { preconditionFailure("Invalid bundled theme: \(error)") }
                let report = PreviewSupport.loadedYearReportModel()
                let cache = RegionOutlinePathCache()
                let regions = LocationsBackgroundArtwork.regions(in: report.ranking)
                return SnapshotCase(
                    name: example.rawValue,
                    configurations: .fullContentPhoneLightDark,
                    measurementReadiness: .immediate,
                    settle: .settledAtLeast(minDuration: 1),
                    onReadyToSnapshot: {
                        for region in regions {
                            _ = await cache.path(for: region, resolution: .small)
                            _ = await cache.path(for: region, resolution: .medium)
                            _ = await cache.path(for: region, resolution: .micro)
                        }
                    },
                ) {
                    LocationsView(report: report)
                        .environment(\.regionOutlinePathCache, cache)
                        .whereBroadwayRoot(themeDocument: theme)
                }
            }
        }
    }

    #Preview("Seasonal theme documents") { LocationsView.SeasonalThemes.snapshotPreviews }
#endif
