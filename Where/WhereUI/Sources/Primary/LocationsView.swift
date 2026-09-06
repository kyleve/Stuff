import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Locations tab: the regions you spend the most days in for the selected year,
/// shown as prominent Liquid Glass cards, with the Elsewhere summary folded in
/// at the bottom (only when there are secondary regions) and a Resolve button
/// that appears — badged — only while there are data issues to fix.
struct LocationsView: View {
    let report: YearReportModel

    @State private var showingResolution = false
    @State private var plannedStayEditorTarget: PlannedStayEditorTarget?
    @State private var isLocationsSurfaceVisible = false
    @State private var isCardSurfaceVisible = false
    @State private var cardPresentation: LocationCardsPresentationModel
    @State private var welcome: LocationWelcomeModel

    /// Drives the region cards' tilt-reactive light sheen. Started/stopped
    /// with the view's lifecycle; a no-op on hardware without device motion.
    @State private var tilt = TiltProvider()

    /// Pairs a tapped card with its pushed calendar so the navigation uses a
    /// matched-geometry zoom (the card expands into the calendar) rather than a
    /// plain slide.
    @Namespace private var calendarTransition

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var isCardSurfaceUncovered: Bool {
        isCardSurfaceVisible
            && !showingResolution
            && plannedStayEditorTarget == nil
            && welcome.presentation == nil
    }

    private var isWelcomeLookupActive: Bool {
        isLocationsSurfaceVisible
            && !showingResolution
            && plannedStayEditorTarget == nil
    }

    init(report: YearReportModel) {
        self.init(
            report: report,
            welcome: LocationWelcomeModel(
                services: report.services,
                preferences: report.preferences,
            ),
        )
    }

    init(report: YearReportModel, welcome: LocationWelcomeModel) {
        self.report = report
        _welcome = State(initialValue: welcome)
        _cardPresentation = State(initialValue: LocationCardsPresentationModel(
            preferences: report.preferences,
            year: report.selectedYear,
        ))
    }

    var body: some View {
        NavigationStack {
            screen
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { isLocationsSurfaceVisible = true }
                .onDisappear { isLocationsSurfaceVisible = false }
                .toolbar {
                    // Resolve is a toolbar action here rather than its own tab:
                    // it appears (badged with the count) only while there are
                    // data issues to fix, and opens the resolution list.
                    if report.dataIssueCount > 0 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingResolution = true
                            } label: {
                                ResolveToolbarLabel(count: report.dataIssueCount)
                            }
                            .accessibilityIdentifier("where_resolution_button")
                        }
                    }
                }
        }
        .accessibilityHidden(welcome.presentation != nil)
        .overlay {
            if let presentation = welcome.presentation {
                LocationWelcomeOverlay(
                    presentation: presentation,
                    dismissAction: welcome.dismiss,
                )
                .transition(stylesheet.locationWelcome.motion.transition)
            }
        }
        .animation(stylesheet.locationWelcome.motion.animation, value: welcome.presentation)
        .task(id: isWelcomeLookupActive) {
            guard isWelcomeLookupActive else { return }
            await welcome.resolve()
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .sheet(isPresented: $showingResolution) {
            ResolutionView(report: report)
        }
        .sheet(item: $plannedStayEditorTarget) { target in
            PlannedStayEditor(
                region: target.region,
                model: report.forecasts,
                driftThreshold: report.driftThreshold,
            )
        }
        // Log View Mode: reveal an inspect badge for the year-report events
        // backing this screen. A no-op in release.
        .debugLogInspectable(WhereLog.session(YearReportModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            case let .failed(error):
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(error.message)
                }
            case .idle, .loaded, .loading:
                if report.ranking.primary.isEmpty {
                    // Distinguish "nothing tracked at all" from "tracked days
                    // exist, but only in non-headline regions" (e.g. all in
                    // `.other`) — otherwise the latter wrongly reads as empty.
                    if report.trackedDayCount == 0 {
                        emptyState
                    } else {
                        elsewhereOnlyState
                    }
                } else {
                    content
                }
        }
    }

    private var content: some View {
        let presentedCards = cardPresentation.presented(report.ranking.primary)

        // `.defaultScrollAnchor(.center)` vertically centers a short list (one or
        // two cards) rather than pinning it to the top, while a longer list still
        // scrolls from the top.
        return ScrollView {
            VStack(spacing: stylesheet.spacing.xxLarge) {
                LocationCardRankingStack(
                    spacing: stylesheet.spacing.xxLarge,
                    presentation: cardPresentation,
                    motion: stylesheet.locationCardStack.overtake,
                ) {
                    ForEach(presentedCards) { item in
                        NavigationLink {
                            calendarDestination(item.region)
                        } label: {
                            RegionSummaryCard(
                                regionDays: item,
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
                            let card = stylesheet.card.regular
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
                    }
                }

                // Fold Elsewhere in at the bottom — only when there's
                // something in it — as an entry card into the full list.
                if !report.ranking.secondary.isEmpty {
                    NavigationLink {
                        ElsewhereView(report: report)
                    } label: {
                        ElsewhereSummaryCard(regionCount: report.ranking.secondary.count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        // The card normally stays clipped to the scrolling viewport. Reveal
        // overflow only while the authored arc, scale, and rotation need it.
        .scrollClipDisabled(cardPresentation.isSpatialOvertakeActive)
        .accessibilityIdentifier("where_root_title")
        .safeAreaInset(edge: .bottom) {
            if report.showsEstimatedTimeAndPlanning, !topForecasts.isEmpty {
                LocationForecastPanel(
                    forecasts: topForecasts,
                    plannedStay: report.forecasts.activePlannedStay,
                    editableRegions: topForecasts.map(\.region),
                    editAction: editPlannedStay,
                    clearAction: report.forecasts.clear,
                    isCollapsible: true,
                )
                .padding(.horizontal)
                .padding(.bottom, stylesheet.spacing.small)
            }
        }
        .onAppear { isCardSurfaceVisible = true }
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

    /// Three forecast rows are independent from the two-card Primary split.
    /// `.other` is a catch-all rather than a place a user can plan around.
    private var topForecasts: [LocationForecast] {
        report.forecasts.leadingForecasts(report: report.report)
    }

    private func estimatedDays(for region: Region) -> Int? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return report.forecasts.forecast(for: region, report: report.report)?.estimatedTotalDays
    }

    private func editPlannedStay(_ region: Region) {
        plannedStayEditorTarget = PlannedStayEditorTarget(region: region)
    }

    private struct PlannedStayEditorTarget: Identifiable {
        let region: Region

        var id: Region {
            region
        }
    }

    /// The region's calendar, pushed as a nested view. It's the zoom
    /// destination: the tapped card expands into it via matched geometry, and the
    /// stack's back gesture collapses it again.
    private func calendarDestination(_ region: Region) -> some View {
        CalendarContentView(focusedRegion: region, report: report)
            .navigationTitle(
                WhereFormat.calendarRegionTitle(region: region, year: report.selectedYear),
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTransition(.zoom(sourceID: region, in: calendarTransition))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(WhereFormat.primaryEmptyTitle(year: report.selectedYear), systemSymbol: .map)
        } description: {
            Text(String(localized: .primaryEmptyDescription))
        }
    }

    private var elsewhereOnlyState: some View {
        ContentUnavailableView {
            Label(String(localized: .primaryElsewhereOnlyTitle), systemSymbol: .globeAmericas)
        } description: {
            Text(WhereFormat.primaryElsewhereOnlyDescription(count: report.trackedDayCount))
        } actions: {
            // Everything tracked is Elsewhere, so surface the list directly —
            // there's no Elsewhere tab to send them to anymore.
            if !report.ranking.secondary.isEmpty {
                NavigationLink(String(localized: .primaryElsewhereOnlyOpen)) {
                    ElsewhereView(report: report)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The Locations toolbar's Resolve affordance: the checklist icon with a count
/// badge. Rendered only while there are issues (the toolbar item is gated on
/// the count), so it always carries a positive `count`.
private struct ResolveToolbarLabel: View {
    let count: Int

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Image(systemSymbol: .checklist)
            .overlay(alignment: .topTrailing) {
                Text(count, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, stylesheet.spacing.xSmall)
                    .padding(.vertical, stylesheet.spacing.xxSmall)
                    .background(.red, in: Capsule())
                    .offset(x: stylesheet.spacing.small, y: -stylesheet.spacing.small)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(String(localized: .tabResolution))
            .accessibilityValue(Text(count, format: .number))
    }
}

#if DEBUG
    extension LocationsView: SnapshotProviding {
        /// The raised settle floor on `Loaded` outlasts the iOS 26 glass toolbar
        /// material adaptation (seen pre-adaptation once on the equivalent
        /// pre-split screen) — same mechanism as `RootView.LoggedIn`.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                LocationsView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(
                name: "PlannedStay",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(report: PreviewSupport.plannedStayYearReportModel())
            }
            whereSnapshot(
                name: "ForecastsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(report: forecastsHiddenReport())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(report: PreviewSupport.emptyYearReportModel())
            }
            whereSnapshot(
                name: "MissingDays",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(report: PreviewSupport.missingDaysYearReportModel())
            }
            whereSnapshot(
                name: "ElsewhereOnly",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(report: PreviewSupport.elsewhereOnlyYearReportModel())
            }
            whereSnapshot(
                name: "DotsHidden",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                LocationsView(
                    report: PreviewSupport.loadedYearReportModelWithLocationDotsHidden(),
                )
            }
            whereSnapshot(
                name: "WelcomeFirst",
                configurations: .phoneLightDark + [
                    SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhone),
                ],
                measurementReadiness: .immediate,
            ) {
                welcomeSnapshot(greeting: .first)
            }
            whereSnapshot(
                name: "WelcomeBack",
                configurations: .phoneLightDark,
                measurementReadiness: .immediate,
            ) {
                welcomeSnapshot(greeting: .returnVisit)
            }
        }

        private static func forecastsHiddenReport() -> YearReportModel {
            PreviewSupport.loadedYearReportModelWithEstimatedTimeHidden()
        }

        private static func welcomeSnapshot(
            greeting: LocationWelcomeModel.Presentation.Greeting,
        ) -> some View {
            let report = PreviewSupport.loadedYearReportModel()
            let welcome = LocationWelcomeModel(
                services: report.services,
                preferences: report.preferences,
            )
            welcome.presentForTesting(region: .california, greeting: greeting)
            return LocationsView(report: report, welcome: welcome)
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
