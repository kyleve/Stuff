import BroadwayUI
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Stable destination ownership around native browse/detail and current-history tabletop layouts.
struct LocationsView: View {
    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    @State private var navigation: SceneNavigationModel.Locations
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var tilt = TiltProvider()
    @Namespace private var calendarTransition
    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        navigation: SceneNavigationModel.Locations? = nil,
        openElsewhere: (() -> Void)? = nil,
    ) {
        self.report = report
        self.openElsewhere = openElsewhere
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Locations())
        _cardPresentation = State(initialValue: LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        @Bindable var navigation = navigation
        AdaptiveHistoryContainer { arrangement in
            if let panes = tabletopPanes(for: arrangement) {
                TabletopHistoryLayout(panes: panes) {
                    calendar(presentation: .month, usesZoomTransition: false)
                } controls: {
                    NavigationStack {
                        browseContent
                            .safeAreaInset(edge: .top, spacing: 0) {
                                HistoryMonthControls(report: report, history: navigation.history)
                            }
                    }
                }
            } else {
                NavigationSplitView(
                    columnVisibility: .constant(.all),
                    preferredCompactColumn: $navigation.compactColumn,
                ) {
                    LocationsBrowsePane(
                        report: report,
                        navigation: navigation,
                        cardPresentation: cardPresentation,
                        tilt: tilt,
                        calendarTransition: calendarTransition,
                        cardVariant: arrangement == .compact ? .regular : .column,
                        openElsewhere: openElsewhere,
                    )
                    .navigationSplitViewColumnWidth(
                        min: stylesheet.adaptiveHistory.minimumControlsWidth,
                        ideal: stylesheet.adaptiveHistory.minimumControlsWidth,
                    )
                } detail: {
                    calendar(
                        presentation: .year,
                        usesZoomTransition: arrangement == .compact,
                    )
                    .navigationSplitViewColumnWidth(
                        min: stylesheet.adaptiveHistory.minimumHistoryWidth,
                        ideal: stylesheet.adaptiveHistory.minimumHistoryWidth,
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .environment(\.horizontalSizeClass, arrangement == .compact ? .compact : .regular)
                .bHorizontalSizeClass(arrangement == .compact ? .compact : .regular)
            }
        }
        .sheet(isPresented: $navigation.showingResolution) {
            ResolutionView(report: report)
        }
        .modifier(PlanningPresentation(report: report, navigation: navigation.history.planning))
    }

    private var browseContent: some View {
        LocationsContent(
            report: report,
            navigation: navigation,
            cardPresentation: cardPresentation,
            tilt: tilt,
            calendarTransition: calendarTransition,
            openElsewhere: openElsewhere,
        )
    }

    /// Drill-ins keep their native stack mounted while their local editors are open.
    /// The custom tabletop composition belongs to the top-level history surface.
    private func tabletopPanes(for arrangement: AdaptiveHistoryArrangement)
        -> AdaptiveHistoryArrangement.Panes?
    {
        guard navigation.browsePath.isEmpty,
              case let .tabletop(panes) = arrangement else { return nil }
        return panes
    }

    private func calendar(
        presentation: CalendarContentView.Presentation,
        usesZoomTransition: Bool,
    ) -> some View {
        @Bindable var navigation = navigation
        return NavigationStack(path: $navigation.detailPath) {
            CalendarContentView(
                focusedRegion: navigation.selectedRegion,
                report: report,
                history: navigation.history,
                presentation: presentation,
                persistenceKey: navigation.selectedRegion.map(CalendarZoomKey.region),
            )
            .id(navigation.selectedRegion)
            .navigationTitle(navigation.selectedRegion.map {
                WhereFormat.calendarRegionTitle(region: $0, year: report.selectedYear)
            } ?? String(localized: .primaryCalendar))
            .navigationBarTitleDisplayMode(.inline)
        }
        .modifier(RegionCalendarTransition(
            region: usesZoomTransition ? navigation.selectedRegion : nil,
            namespace: calendarTransition,
        ))
    }
}

/// Native split navigation uses the same card zoom when its detail collapses to a push.
private struct RegionCalendarTransition: ViewModifier {
    let region: Region?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if let region {
            content.navigationTransition(.zoom(sourceID: region, in: namespace))
        } else {
            content
        }
    }
}

/// The stable browse stack. Pushed flows retain their native navigation and draft state.
struct LocationsBrowsePane: View {
    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    @State private var navigation: SceneNavigationModel.Locations
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var tilt: TiltProvider
    @Namespace private var localTransition
    private let transition: Namespace.ID?
    let cardVariant: WhereStylesheet.CardStyle.Variant

    init(
        report: YearReportModel,
        navigation: SceneNavigationModel.Locations? = nil,
        cardPresentation: LocationCardsPresentationModel? = nil,
        tilt: TiltProvider? = nil,
        calendarTransition: Namespace.ID? = nil,
        cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        openElsewhere: (() -> Void)? = nil,
    ) {
        self.report = report
        self.openElsewhere = openElsewhere
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Locations())
        _cardPresentation = State(initialValue: cardPresentation ?? LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
        _tilt = State(initialValue: tilt ?? TiltProvider())
        transition = calendarTransition
        self.cardVariant = cardVariant
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.browsePath) {
            LocationsContent(
                report: report,
                navigation: navigation,
                cardPresentation: cardPresentation,
                tilt: tilt,
                calendarTransition: transition ?? localTransition,
                cardVariant: cardVariant,
                openElsewhere: openElsewhere,
            )
            .navigationDestination(for: SceneNavigationModel.Locations.Destination
                .self)
            { destination in
                switch destination {
                    case .elsewhere: ElsewhereView(report: report)
                    case let .flight(review): FlightDayDetailView(
                            review: review,
                            report: report,
                        )
                }
            }
        }
    }
}

/// Locations tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards, with the Elsewhere summary folded in
/// at the bottom (only when there are secondary regions), plus toolbar actions
/// for planned stays and any data issues that need resolution.
struct LocationsContent: View {
    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    let cardVariant: WhereStylesheet.CardStyle.Variant

    @State private var navigation: SceneNavigationModel.Locations
    @State private var isCardSurfaceVisible = false
    @State private var cardPresentation: LocationCardsPresentationModel

    /// Drives the region cards' tilt-reactive light sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Pairs a tapped card with its pushed calendar so the navigation uses a
    /// matched-geometry zoom (the card expands into the calendar) rather than a
    /// plain slide.
    @Namespace private var localCalendarTransition
    private let transition: Namespace.ID?
    private var calendarTransition: Namespace.ID {
        transition ?? localCalendarTransition
    }

    @Environment(\.stylesheet.card.regular.surface) private var cardSurface

    private var isCardSurfaceUncovered: Bool {
        isCardSurfaceVisible
            && !navigation.showingResolution
            && navigation.planningDestination == nil
    }

    init(
        report: YearReportModel,
        navigation: SceneNavigationModel.Locations? = nil,
        cardPresentation: LocationCardsPresentationModel? = nil,
        tilt: TiltProvider? = nil,
        calendarTransition: Namespace.ID? = nil,
        cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        openElsewhere: (() -> Void)? = nil,
    ) {
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Locations())
        self.report = report
        self.openElsewhere = openElsewhere
        self.cardVariant = cardVariant
        transition = calendarTransition
        _tilt = State(initialValue: tilt ?? TiltProvider())
        _cardPresentation = State(initialValue: cardPresentation ?? LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        @Bindable var navigation = navigation
        screen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LocationsBackground(regions: backgroundRegions)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Pending reviews remain accessible without increasing
                    // the actionable issue badge.
                    if report.dataIssueCount > 0 || report.hasCorrectionReviews {
                        Button {
                            navigation.showingResolution = true
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
                            navigation.planningDestination = .list
                        }
                        .accessibilityIdentifier("where_planning_menu")
                    }
                }
            }
            .observesTilt(tilt, enabled: isCardSurfaceUncovered && cardSurface.usesReflection)
            .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil, .failed:
                LocationsStateView(
                    report: report,
                    planningAction: openPlanning,
                    openReview: { navigation.open(.flight($0)) },
                    openElsewhere: openElsewhere,
                )
            case .idle, .loaded, .loading:
                if report.locationRegions.isEmpty {
                    LocationsStateView(
                        report: report,
                        planningAction: openPlanning,
                        openReview: { navigation.open(.flight($0)) },
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
                        navigation: navigation,
                        cardVariant: cardVariant,
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
        navigation.planningDestination = .list
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
                name: "BrowseColumn",
                report: PreviewSupport.loadedYearReportModel(),
                configurations: [SnapshotConfiguration(device: AdaptiveHistorySnapshotFixture
                        .browseColumn)],
                cardVariant: .column,
            )
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
                LocationsBrowsePane(report: PreviewSupport.plannedStayYearReportModel())
            }
            whereSnapshot(
                name: "ForecastsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsBrowsePane(report: forecastsHiddenReport())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsBrowsePane(report: PreviewSupport.emptyYearReportModel())
            }
            whereSnapshot(
                name: "MissingDays",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsBrowsePane(report: PreviewSupport.missingDaysYearReportModel())
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
                LocationsBrowsePane(
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
            cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
            openElsewhere _: (() -> Void)? = nil,
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
                LocationsBrowsePane(report: report, cardVariant: cardVariant)
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
