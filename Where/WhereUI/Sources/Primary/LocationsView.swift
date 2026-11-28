import BroadwayUI
import Observation
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Stable selection and sheet ownership around the adaptive Locations layouts.
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

        func toggleSelection(of region: Region) {
            if selectedRegion == region {
                selectedRegion = nil
                compactColumn = .sidebar
            } else {
                select(region: region)
            }
        }
    }

    enum ScrollRole: Hashable { case calendar }

    /// Each opening has a distinct ID because an earlier opening may still be animating.
    struct CalendarSelection: Identifiable, Hashable {
        struct ID: Hashable {
            private let value = UUID()
        }

        let id = ID()
        let region: Region
    }

    /// Keeps the zoom state of the selected calendar and any calendars still animating out.
    @MainActor @Observable
    final class CalendarPresentations {
        private(set) var selected: CalendarSelection?
        private var presentations: [CalendarSelection.ID: CalendarPresentationState] = [:]

        func select(region: Region, presentation: CalendarPresentationState) {
            let selection = CalendarSelection(region: region)
            presentations[selection.id] = presentation
            selected = selection
        }

        func deselect() {
            selected = nil
        }

        subscript(_ selection: CalendarSelection) -> CalendarPresentationState? {
            presentations[selection.id]
        }

        func discard(_ selection: CalendarSelection) {
            guard selection.id != selected?.id else { return }
            presentations.removeValue(forKey: selection.id)
        }

        func retain(_ displayed: [CalendarSelection]) {
            let visibleIDs = Set(displayed.map(\.id))
            presentations = presentations
                .filter { $0.key == selected?.id || visibleIDs.contains($0.key) }
        }
    }

    let report: YearReportModel
    var openElsewhere: (() -> Void)?
    @State private var navigation: LocationsView.Navigation
    @State private var calendarPresentations: CalendarPresentations
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
        _calendarPresentations = State(initialValue: Self.makeCalendarPresentations(
            for: navigation.selectedRegion,
            report: report,
        ))
        _cardPresentation = State(initialValue: LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        @Bindable var navigation = navigation
        AdaptivePaneContainer { arrangement in
            if report.report == nil {
                browsePane
            } else if arrangement == .columns {
                NavigationStack {
                    LocationsColumns(browseWidth: stylesheet.adaptivePane.minimumControlsWidth) {
                        expandedBrowseContent
                    } detail: {
                        detailContent(arrangement: .columns)
                    }
                    .navigationTitle(selectedCalendarTitle ?? "")
                    .navigationBarTitleDisplayMode(.inline)
                    .containerBackground(.clear, for: .navigation)
                }
            } else {
                NavigationSplitView(
                    columnVisibility: .constant(.all),
                    preferredCompactColumn: $navigation.compactColumn,
                ) {
                    browsePane
                        .containerBackground(.clear, for: .navigation)
                        .containerBackground(.clear, for: .navigationSplitView)
                        .toolbar(removing: .sidebarToggle)
                } detail: {
                    NavigationStack {
                        detailContent(arrangement: .compact)
                            .navigationTitle(
                                selectedCalendarTitle ?? String(localized: .primaryCalendar),
                            )
                            .navigationBarTitleDisplayMode(.inline)
                            .containerBackground(.clear, for: .navigation)
                    }
                    .modifier(RegionCalendarTransition(
                        region: navigation.selectedRegion,
                        namespace: calendarTransition,
                    ))
                    .containerBackground(.clear, for: .navigation)
                }
                .navigationSplitViewStyle(.balanced)
                .environment(\.horizontalSizeClass, .compact)
                .bHorizontalSizeClass(.compact)
            }
        }
        .visitedRegionsBackground(report)
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
        .onChange(of: navigation.selectedRegion) { _, region in
            Self.selectCalendar(for: region, in: calendarPresentations, report: report)
        }
        .environment(calendarPresentations)
    }

    static func makeCalendarPresentations(
        for region: Region?,
        report: YearReportModel,
    ) -> CalendarPresentations {
        let calendars = CalendarPresentations()
        selectCalendar(for: region, in: calendars, report: report)
        return calendars
    }

    private static func selectCalendar(
        for region: Region?,
        in calendars: CalendarPresentations,
        report: YearReportModel,
    ) {
        guard let region else {
            calendars.deselect()
            return
        }
        let overview = CalendarModel(report: report, persistenceKey: .region(region))
            .isOverview(fallback: false)
        calendars.select(
            region: region,
            presentation: CalendarPresentationState(mode: overview ? .overview : .detail),
        )
    }

    private var selectedCalendarTitle: String? {
        navigation.selectedRegion.map {
            WhereFormat.calendarRegionTitle(region: $0, year: report.selectedYear)
        }
    }

    private var browsePane: LocationsBrowsePane {
        LocationsBrowsePane(
            report: report,
            navigation: navigation,
            cardPresentation: cardPresentation,
            tilt: tilt,
            calendarTransition: calendarTransition,
            openElsewhere: openElsewhere,
        )
    }

    private var expandedBrowseContent: LocationsContent {
        LocationsContent(
            report: report,
            navigation: navigation,
            cardPresentation: cardPresentation,
            tilt: tilt,
            calendarTransition: calendarTransition,
            cardVariant: .column,
            showsSelection: true,
            showsToolbarActions: false,
            openElsewhere: openElsewhere,
        )
    }

    private func detailContent(arrangement: AdaptivePaneArrangement) -> LocationsDetailContent {
        LocationsDetailContent(
            report: report,
            navigation: navigation,
            selection: calendarPresentations.selected,
            arrangement: arrangement,
        )
    }
}

private struct LocationsColumns<Browse: View, Detail: View>: View {
    let browseWidth: CGFloat
    @ViewBuilder let browse: () -> Browse
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            browse()
                .frame(width: browseWidth)
                // Draw the card halos above the neighboring calendar edge.
                .zIndex(1)
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The compact calendar push zooms from its region card.
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
            .containerBackground(.clear, for: .navigation)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsToolbarActions {
                    LocationsToolbar(report: report, navigation: navigation)
                }
            }
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
                browsePane(report: PreviewSupport.plannedStayYearReportModel())
            }
            whereSnapshot(
                name: "ForecastsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                browsePane(report: forecastsHiddenReport())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                browsePane(report: PreviewSupport.emptyYearReportModel())
            }
            whereSnapshot(
                name: "MissingDays",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                browsePane(report: PreviewSupport.missingDaysYearReportModel())
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
                browsePane(
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
            let cache = PreviewSupport.snapshotArtworkCache
            let regions = LocationsBackgroundArtwork.regions(in: report.ranking)
            return whereSnapshot(
                name: name,
                configurations: configurations,
                theme: theme,
                measurementReadiness: .immediate,
                // Prepared fixtures remeasured on Xcode 27.2 / iOS 27.2 (2026-11-16).
                // Keep this mode so annotations still settle between their two parses.
                settle: .settledAtLeast(minDuration: 0.25),
                prepareForCapture: {
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
                browsePane(
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

        private static func browsePane(
            report: YearReportModel,
            navigation: LocationsView.Navigation? = nil,
            cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        ) -> some View {
            LocationsBrowsePane(report: report, navigation: navigation, cardVariant: cardVariant)
                .visitedRegionsBackground(report)
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

/// Shared actions for the expanded toolbar or the visible compact screen.
struct LocationsToolbar: ToolbarContent {
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
