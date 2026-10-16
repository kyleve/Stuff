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
    @State private var navigation: SceneNavigationModel.Locations
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var tilt = TiltProvider()
    @Namespace private var calendarTransition
    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, navigation: SceneNavigationModel.Locations? = nil) {
        self.report = report
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
            )
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
    ) {
        self.report = report
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

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

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
    ) {
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Locations())
        self.report = report
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
            .onAppear { tilt.start() }
            .onDisappear { tilt.stop() }
            // Log View Mode: reveal an inspect badge for the year-report events
            // backing this screen. A no-op in release.
            .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                stateWithFlightNotice {
                    AppIconLoadingView(caption: String(localized: .primaryLoading))
                }
            case let .failed(error):
                stateWithFlightNotice {
                    ContentUnavailableView {
                        Label(
                            String(localized: .commonLoadErrorTitle),
                            systemSymbol: .exclamationmarkIcloud,
                        )
                    } description: {
                        Text(error.message)
                    }
                }
            case .idle, .loaded, .loading:
                if report.ranking.primary.isEmpty {
                    // Distinguish "nothing tracked at all" from "tracked days
                    // exist, but only in non-headline regions" (e.g. all in
                    // `.other`) — otherwise the latter wrongly reads as empty.
                    if report.trackedDayCount == 0 {
                        stateWithFlightNotice { emptyState }
                    } else {
                        stateWithFlightNotice { elsewhereOnlyState }
                    }
                } else {
                    content
                }
        }
    }

    @ViewBuilder
    private var flightNotice: some View {
        if let review = report.liveFlightReview {
            Button {
                navigation.open(.flight(review))
            } label: {
                FlightStatusBanner(
                    review: review,
                    deviceLabel: report.liveFlightAssessment(in: review)
                        .map(report.flightDeviceLabel),
                    flight: report.liveFlightAssessment(in: review),
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: .flightStatusOpenReview))
        }
    }

    /// Keep short states centered and let a flight notice or larger text scroll.
    private func stateWithFlightNotice(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                flightNotice
                content()
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top, for: .alignment)
    }

    private var content: some View {
        @Bindable var navigation = navigation
        let presentedCards = cardPresentation.presented(report.ranking.primary)

        // Keep the flight notice immediately below navigation. Without a notice,
        // a short card list retains its centered presentation.
        return ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                flightNotice

                LocationCardRankingStack(
                    spacing: stylesheet.spacing.xxLarge,
                    presentation: cardPresentation,
                    motion: stylesheet.locationCardStack.overtake,
                ) {
                    ForEach(presentedCards) { item in
                        Button {
                            navigation.select(region: item.region)
                        } label: {
                            RegionSummaryCard(
                                regionDays: item,
                                variant: cardVariant,
                                interactive: true,
                                yearLength: report.daysInSelectedYear,
                                estimatedDays: estimatedDays(for: item.region),
                                year: report.selectedYear,
                                tilt: tilt,
                                recordedPoints: report.primaryRegionLocations?
                                    .pointsByRegion[item.region] ?? [],
                                showsRecordedPoints: report.showsRecordedLocationDots,
                                recordedPointsID: report.primaryRegionLocations?.id,
                            )
                        }
                        // Plain so the card's interactive Liquid Glass owns
                        // the press feel rather than the button adding its own.
                        .buttonStyle(.plain)
                        .historySelection(
                            navigation.selectedRegion == item.region,
                            cornerRadius: stylesheet.card[cardVariant].cornerRadius,
                        )
                        // The card is the zoom source: tapping it expands the
                        // card into the pushed calendar (matched geometry). The
                        // configuration re-states the card's rounded shape and
                        // its glow/lift shadows so the transition interpolates
                        // them — without it, the zoom clips the source to a bare
                        // rectangle and the card's soft shadow pops on/off.
                        .matchedTransitionSource(
                            id: item.region,
                            in: calendarTransition,
                        ) { source in
                            let card = stylesheet.card[cardVariant]
                            let tint = regionStyles.style(for: item.region).tint
                            return source
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: card.cornerRadius,
                                        style: .continuous,
                                    ),
                                )
                                .shadow(
                                    color: tint.opacity(card.glow.opacity),
                                    radius: card.glow.radius,
                                )
                                .shadow(
                                    color: tint.opacity(card.lift.opacity),
                                    radius: card.lift.radius,
                                    y: card.lift.offsetY,
                                )
                        }
                        .accessibilityHint(String(localized: .primaryCardCalendarHint))
                        .locationCardOvertakeEffect(
                            region: item.region,
                            presentation: cardPresentation,
                            motion: stylesheet.locationCardStack.overtake,
                        )
                        .locationCardRankingRegion(item.region)
                        .id(item.region)
                    }
                }
                .scrollTargetLayout()

                estimatePanel

                // Fold Elsewhere in at the bottom — only when there's
                // something in it — as an entry card into the full list.
                if !report.ranking.secondary.isEmpty {
                    Button {
                        navigation.open(.elsewhere)
                    } label: {
                        ElsewhereSummaryCard(regions: report.ranking.secondary.map(\.region))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top, for: .alignment)
        .scrollPosition($navigation.scrollPosition)
        .onScrollTargetVisibilityChange(idType: Region.self, threshold: 0.01) { regions in
            guard navigation.scrollPosition.isPositionedByUser else { return }
            navigation.visibleRegion = presentedCards.first { regions.contains($0.region) }?.region
        }
        .scrollBounceBehavior(.basedOnSize)
        // The card normally stays clipped to the scrolling viewport. Reveal
        // overflow only while the authored arc, scale, and rotation need it.
        .scrollClipDisabled(cardPresentation.isSpatialOvertakeActive)
        .accessibilityIdentifier("where_root_title")
        .onAppear {
            isCardSurfaceVisible = true
            navigation.restoreBrowsePosition()
        }
        .onDisappear { isCardSurfaceVisible = false }
        // Count, order, flourish, persistence, and haptic all share this one
        // visibility-aware delayed reconciliation.
        .reconcilesLocationCards(
            current: report.ranking.primary,
            year: report.selectedYear,
            isVisible: isCardSurfaceUncovered,
            presentation: cardPresentation,
            motion: stylesheet.locationCardStack.overtake,
        )
    }

    private var backgroundRegions: [Region] {
        switch report.loadState {
            case .failed:
                []
            case .idle, .loaded, .loading:
                LocationsBackgroundArtwork.regions(in: report.ranking)
        }
    }

    private var primaryRegions: [Region] {
        report.ranking.primary.map(\.region).filter { $0 != .other }
    }

    private var showsPlanningMenu: Bool {
        report.showsEstimatedTimeAndPlanning
    }

    private func estimatedDays(for region: Region) -> DayBounds? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return report.forecasts.forecast(for: region, report: report.report)?.estimatedTotalDays
    }

    @ViewBuilder
    private var estimatePanel: some View {
        let forecasts = report.forecasts.leadingForecasts(report: report.report)
        if report.showsEstimatedTimeAndPlanning, !forecasts.isEmpty {
            LocationForecastPanel(
                forecasts: forecasts,
                microprintRegions: primaryRegions,
                homeRegion: report.forecasts.planning.homeRegion,
                planningAction: { navigation.planningDestination = .list },
                isCollapsible: true,
            )
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: stylesheet.spacing.large) {
                ContentUnavailableView {
                    Label(
                        WhereFormat.primaryEmptyTitle(year: report.selectedYear),
                        systemSymbol: .map,
                    )
                } description: {
                    Text(String(localized: .primaryEmptyDescription))
                }
                estimatePanel
            }
            .padding()
        }
    }

    private var elsewhereOnlyState: some View {
        ScrollView {
            VStack(spacing: stylesheet.spacing.large) {
                ContentUnavailableView {
                    Label(
                        String(localized: .primaryElsewhereOnlyTitle),
                        systemSymbol: .globeAmericas,
                    )
                } description: {
                    Text(WhereFormat.primaryElsewhereOnlyDescription(count: report.trackedDayCount))
                } actions: {
                    if !report.ranking.secondary.isEmpty {
                        Button(String(localized: .primaryElsewhereOnlyOpen)) {
                            navigation.open(.elsewhere)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                estimatePanel
            }
            .padding()
        }
    }
}

/// The Locations toolbar's Resolve affordance: the checklist icon with a count
/// badge for actionable issues. Pending reviews keep the unbadged icon available.
private struct ResolveToolbarLabel: View {
    let count: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Image(systemSymbol: .checklist)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, stylesheet.spacing.xSmall)
                        .padding(.vertical, stylesheet.spacing.xxSmall)
                        .background(.red, in: Capsule())
                        .offset(x: stylesheet.spacing.small, y: -stylesheet.spacing.small)
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
                configurations: .fullContentScreenDefaults,
            )
            artworkSnapshot(
                name: "Loaded",
                report: PreviewSupport.loadedYearReportModel(),
                configurations: .fullContentScreenDefaults,
            )
            for state in [FlightReviewPreviewState.flightLikely, .stale, .ready, .completed] {
                artworkSnapshot(
                    name: "Flight-" + state.rawValue,
                    report: PreviewSupport.flightYearReportModel(state: state),
                    configurations: state == .flightLikely
                        ? .fullContentScreenDefaults : .fullContentPhoneLightDark,
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
                LocationsBrowsePane(report: PreviewSupport.elsewhereOnlyYearReportModel())
            }
            whereSnapshot(
                name: "ElsewhereWithHome",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                let report = PreviewSupport.elsewhereOnlyYearReportModel()
                report.forecasts.setPlanning(PlanningSnapshot(stays: [], homeRegion: .california))
                return LocationsBrowsePane(report: report)
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
        }

        private static func artworkSnapshot(
            name: String,
            report: YearReportModel,
            configurations: [SnapshotConfiguration],
            cardVariant: WhereStylesheet.CardStyle.Variant = .regular,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let regions = LocationsBackgroundArtwork.regions(in: report.ranking)
            return whereSnapshot(
                name: name,
                configurations: configurations,
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
                .push(to: ElsewhereView.flyoverID),
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
