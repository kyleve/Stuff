import BroadwayUI
import Observation
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Stable selection and sheet ownership around native browse/detail navigation.
struct LocationsView: View {
    @MainActor @Observable
    final class Navigation {
        var selectedRegion: Region?
        var compactColumn = NavigationSplitViewColumn.sidebar
        var flightReview: GPSCorrectionReview?

        var showingResolution = false
        var planningDestination: PlannedStaysDestination?

        func select(region: Region) {
            guard selectedRegion != region || compactColumn != .detail else { return }
            selectedRegion = region
            compactColumn = .detail
        }
    }

    enum ScrollRole: Hashable { case calendar }

    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    @State private var navigation: LocationsView.Navigation
    @State private var calendarPresentation: CalendarPresentationState
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var tilt = TiltProvider()
    @Namespace private var calendarTransition
    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        navigation: LocationsView.Navigation? = nil,
        initialRegion: Region? = nil,
        openElsewhere: (() -> Void)? = nil,
    ) {
        self.report = report
        self.openElsewhere = openElsewhere
        let navigation = navigation ?? LocationsView.Navigation()
        if let initialRegion { navigation.select(region: initialRegion) }
        _navigation = State(initialValue: navigation)
        _calendarPresentation = State(initialValue: CalendarPresentationState(mode: CalendarModel(
            report: report,
            persistenceKey: navigation.selectedRegion.map(CalendarZoomKey.region),
        ).isOverview(fallback: false) ? .overview : .detail))
        _cardPresentation = State(initialValue: LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        @Bindable var navigation = navigation
        AdaptivePaneContainer { arrangement in
            if report.report == nil {
                LocationsBrowsePane(
                    report: report,
                    navigation: navigation,
                    cardPresentation: cardPresentation,
                    tilt: tilt,
                    calendarTransition: calendarTransition,
                    openElsewhere: openElsewhere,
                )
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
                        showsSelection: arrangement != .compact,
                        showsToolbarActions: arrangement == .compact,
                        openElsewhere: openElsewhere,
                    )
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(
                        min: stylesheet.adaptivePane.minimumControlsWidth,
                        ideal: stylesheet.adaptivePane.minimumControlsWidth,
                    )
                } detail: {
                    calendar(
                        showsEstimateCard: arrangement == .compact,
                        usesZoomTransition: arrangement == .compact,
                    )
                    .navigationSplitViewColumnWidth(
                        min: stylesheet.adaptivePane.minimumDetailWidth,
                        ideal: stylesheet.adaptivePane.minimumDetailWidth,
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .environment(\.horizontalSizeClass, arrangement == .compact ? .compact : .regular)
                .bHorizontalSizeClass(arrangement == .compact ? .compact : .regular)
            }
        }
        .whereThemeActivity(!navigation.showingResolution && navigation
            .planningDestination == nil && navigation.flightReview == nil)
        .sheet(item: $navigation.flightReview) { review in
            NavigationStack {
                FlightDayDetailView(review: review, report: report)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { navigation.flightReview = nil }
                    } }
            }
        }
        .sheet(isPresented: $navigation.showingResolution) {
            ResolutionView(report: report)
        }
        .modifier(PlanningPresentation(
            report: report,
            destination: $navigation.planningDestination,
        ))
        .onChange(of: navigation.selectedRegion) {
            calendarPresentation = CalendarPresentationState(mode: CalendarModel(
                report: report,
                persistenceKey: navigation.selectedRegion.map(CalendarZoomKey.region),
            ).isOverview(fallback: false) ? .overview : .detail)
        }
    }

    private func calendar(
        showsEstimateCard: Bool,
        usesZoomTransition: Bool,
    ) -> some View {
        @Bindable var navigation = navigation
        return NavigationStack {
            CalendarContentView(
                focusedRegion: navigation.selectedRegion,
                report: report,
                showsEstimateCard: showsEstimateCard,
                showsPlanningAction: false,
                presentationState: calendarPresentation,
                persistenceKey: navigation.selectedRegion.map(CalendarZoomKey.region),
                scrollRole: ScrollRole.calendar,
                planningDestination: $navigation.planningDestination,
            )
            .toolbar { LocationsToolbar(report: report, navigation: navigation) }
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
    @State private var navigation: LocationsView.Navigation
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var tilt: TiltProvider
    @Namespace private var localTransition
    private let transition: Namespace.ID?
    let cardVariant: WhereStylesheet.CardStyle.Variant
    let showsSelection: Bool
    let showsToolbarActions: Bool

    init(
        report: YearReportModel,
        navigation: LocationsView.Navigation? = nil,
        cardPresentation: LocationCardsPresentationModel? = nil,
        tilt: TiltProvider? = nil,
        calendarTransition: Namespace.ID? = nil,
        cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        showsSelection: Bool = false,
        showsToolbarActions: Bool = true,
        openElsewhere: (() -> Void)? = nil,
    ) {
        self.report = report
        self.openElsewhere = openElsewhere
        _navigation = State(initialValue: navigation ?? LocationsView.Navigation())
        _cardPresentation = State(initialValue: cardPresentation ?? LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
        _tilt = State(initialValue: tilt ?? TiltProvider())
        transition = calendarTransition
        self.cardVariant = cardVariant
        self.showsSelection = showsSelection
        self.showsToolbarActions = showsToolbarActions
    }

    var body: some View {
        NavigationStack {
            LocationsContent(
                report: report,
                navigation: navigation,
                cardPresentation: cardPresentation,
                tilt: tilt,
                calendarTransition: transition ?? localTransition,
                cardVariant: cardVariant,
                showsSelection: showsSelection,
                showsToolbarActions: showsToolbarActions,
                openElsewhere: openElsewhere,
            )
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
    let showsSelection: Bool
    let showsToolbarActions: Bool

    @State private var navigation: LocationsView.Navigation
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
            && navigation.flightReview == nil
            && !navigation.showingResolution
            && navigation.planningDestination == nil
    }

    init(
        report: YearReportModel,
        navigation: LocationsView.Navigation? = nil,
        cardPresentation: LocationCardsPresentationModel? = nil,
        tilt: TiltProvider? = nil,
        calendarTransition: Namespace.ID? = nil,
        cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        showsSelection: Bool = false,
        showsToolbarActions: Bool = true,
        openElsewhere: (() -> Void)? = nil,
    ) {
        _navigation = State(initialValue: navigation ?? LocationsView.Navigation())
        self.report = report
        self.openElsewhere = openElsewhere
        self.cardVariant = cardVariant
        self.showsSelection = showsSelection
        self.showsToolbarActions = showsToolbarActions
        transition = calendarTransition
        _tilt = State(initialValue: tilt ?? TiltProvider())
        _cardPresentation = State(initialValue: cardPresentation ?? LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        screen
            .modifier(WhereComponentTextStyle(role: .locations))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LocationsBackground(regions: backgroundRegions)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsToolbarActions {
                    LocationsToolbar(report: report, navigation: navigation)
                }
            }
            .whereThemeActivity(!navigation.showingResolution && navigation
                .planningDestination == nil && navigation.flightReview == nil)
            .observesTilt(tilt, enabled: isCardSurfaceUncovered && cardSurface.usesReflection)
            .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil, .failed where report.report == nil:
                LocationsStateView(
                    report: report,
                    planningAction: openPlanning,
                    openReview: { navigation.flightReview = $0 },
                    openElsewhere: openElsewhere,
                )
            case .idle, .loaded, .loading, .failed:
                if report.locationRegions.isEmpty {
                    LocationsStateView(
                        report: report,
                        planningAction: openPlanning,
                        openReview: { navigation.flightReview = $0 },
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
                        showsSelection: showsSelection,
                    )
                }
        }
    }

    private var backgroundRegions: [Region] {
        LocationsBackgroundArtwork.regions(in: report.ranking)
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
            // Halloween has full-screen and accessibility coverage in MainTabs snapshots.
            for theme in [WhereTheme.alternate] {
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
                configurations: [SnapshotConfiguration(device: DuoLayoutSnapshotFixture
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
            selectedRegion: Region? = nil,
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
                let navigation = LocationsView.Navigation()
                let _ = navigation.selectedRegion = selectedRegion
                LocationsBrowsePane(
                    report: report,
                    navigation: navigation,
                    cardVariant: cardVariant,
                )
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

/// Shared screen actions appear in the trailing column, or on the visible compact screen.
private struct LocationsToolbar: ToolbarContent {
    let report: YearReportModel
    let navigation: LocationsView.Navigation

    var body: some ToolbarContent {
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

            if report.showsEstimatedTimeAndPlanning {
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
}

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
                    LocationsBrowsePane(report: report)
                        .environment(\.regionOutlinePathCache, cache)
                        .whereBroadwayRoot(themeDocument: theme)
                }
            }
        }
    }

    #Preview("Seasonal theme documents") { LocationsView.SeasonalThemes.snapshotPreviews }
#endif
