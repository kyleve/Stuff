import BroadwayUI
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
@_spi(Testing) import WhereCore

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day, and a per-month footer tallying the days spent
/// in each region. Chrome-free (no `NavigationStack`) so the host owns the
/// navigation: the Your Year tab embeds it inline, and the Locations tab pushes
/// it — region-focused, with a title — as the zoom destination of a tapped card.
struct CalendarContentView: View {
    private let showsEstimateCard: Bool
    private let showsPlanningAction: Bool
    private let showsZoomAction: Bool
    private let onPresentationReady: (() -> Void)?
    enum ScrollRole: Hashable {
        case detail
    }

    struct ScrollContext: Hashable { let region: Region?; let year: Int }
    private let model: CalendarModel
    private let suppliedPlanningDestination: Binding<PlannedStaysDestination?>?
    @State private var localPlanningDestination: PlannedStaysDestination?
    private var planningDestination: Binding<PlannedStaysDestination?> {
        suppliedPlanningDestination ?? $localPlanningDestination
    }

    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel

    @Environment(\.stylesheet) private var stylesheet
    @State private var monthsLoad: Result<[CalendarMonth], Error>?
    @State private var localPresentation: CalendarPresentationState
    private let suppliedPresentation: CalendarPresentationState?
    private var presentation: CalendarPresentationState {
        suppliedPresentation ?? localPresentation
    }

    @AccessibilityFocusState private var focusedTarget: CalendarPresentationState.Target?
    @State private var zoom = CalendarZoomTransitionState()
    @BScrollPosition<
        CalendarPresentationState.Target,
        CalendarContentView.ScrollContext
    > private var detailPosition: ScrollPosition
    @State private var overviewPosition = ScrollPosition(
        idType: CalendarPresentationState.Target.self,
        edge: .top,
    )
    private var detailTarget: CalendarPresentationState
        .Target?
    {
        detailPosition.viewID(type: CalendarPresentationState.Target.self)
    }

    private var calendarPosition: Binding<ScrollPosition> {
        presentation.mode == .overview ? $overviewPosition : $detailPosition
    }

    @State private var scrollOffset = CGPoint.zero

    /// A nil persistence key keeps zoom session-only, including in previews.
    init(
        focusedRegion: Region? = nil,
        report: YearReportModel,
        showsEstimateCard: Bool = true,
        showsPlanningAction: Bool = true,
        showsZoomAction: Bool = true,
        presentationState: CalendarPresentationState? = nil,
        initialMode: CalendarPresentationState.Mode = .detail,
        persistenceKey: CalendarZoomKey? = nil,
        scrollRole: some Hashable = ScrollRole.detail,
        planningDestination: Binding<PlannedStaysDestination?>? = nil,
        onPresentationReady: (() -> Void)? = nil,
    ) {
        self.focusedRegion = focusedRegion
        self.report = report
        self.showsEstimateCard = showsEstimateCard
        self.showsPlanningAction = showsPlanningAction
        self.showsZoomAction = showsZoomAction
        self.onPresentationReady = onPresentationReady
        suppliedPresentation = presentationState
        suppliedPlanningDestination = planningDestination
        let model = CalendarModel(report: report, persistenceKey: persistenceKey)
        self.model = model
        _localPresentation =
            State(initialValue: CalendarPresentationState(mode: model
                    .isOverview(fallback: initialMode == .overview) ? .overview : .detail))
        _detailPosition = BScrollPosition(
            Self.self,
            role: scrollRole,
            context: { ScrollContext(region: focusedRegion, year: report.selectedYear) },
            idType: CalendarPresentationState.Target.self,
        )
    }

    private static let logger = WhereLog.session(CalendarViewLog.self)

    var body: some View {
        Group {
            if let yearReport = report.report {
                Group {
                    switch monthsLoad {
                        case let .success(months):
                            CalendarScrollView(
                                months: months,
                                report: report,
                                focusedRegion: focusedRegion,
                                forecasts: calendarForecasts,
                                showsEstimateCard: showsEstimateCard,
                                presentation: presentation,
                                zoom: zoom,
                                position: calendarPosition,
                                focusedTarget: $focusedTarget,
                                scrollOffset: $scrollOffset,
                                onExpand: { target in changeZoom { expand(target) } },
                                onPinch: { magnification, destination in
                                    changeZoom { finishPinch(
                                        magnification: magnification,
                                        destination: destination,
                                    ) }
                                },
                                onPlan: { planningDestination.wrappedValue = .list },
                                restorePosition: restorePosition,
                                onPresentationReady: onPresentationReady,
                                finishZoom: finishZoom,
                            )
                        case let .failure(error):
                            CalendarUnavailableContent(
                                description: String(localized: .calendarUnavailableDescription),
                            )
                            .onAppear {
                                Self.logger.layoutFailed(error: .restricted(
                                    .errorDetails,
                                    error,
                                ))
                            }
                            .onAppear { onPresentationReady?() }
                        case nil:
                            AppIconLoadingView(caption: String(localized: .primaryLoading))
                    }
                }
                .task(id: model.loadID(for: yearReport, focusedRegion: focusedRegion)) {
                    zoom.cancel()
                    let result = model.months(from: yearReport, focusedRegion: focusedRegion)
                    guard !Task.isCancelled else { return }
                    monthsLoad = result
                }
            } else if report.loadState == .loading {
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            } else if case let .failed(error) = report.loadState {
                CalendarUnavailableContent(description: error.message)
            } else {
                CalendarUnavailableContent(
                    description: String(localized: .calendarUnavailableDescription),
                )
                .onAppear {
                    Self.logger.openedWithoutReport(
                        loadState: .restricted(
                            .technicalState,
                            String(describing: report.loadState),
                        ),
                    )
                }
            }
        }
        // Log View Mode: reveal an inspect badge for this calendar's events. A
        // no-op in release.
        .debugLogInspectable(WhereLog.session(CalendarViewLog.self))
        .modifier(PlanningPresentation(
            report: report,
            destination: planningDestination,
            isEnabled: suppliedPlanningDestination == nil,
        ))
        .toolbar {
            if showsZoomAction {
                ToolbarItem(placement: .topBarTrailing) {
                    CalendarZoomButton(
                        mode: presentation.mode,
                        disabled: monthsLoad == nil || zoom.phase != nil,
                    ) {
                        changeZoom { toggleZoom() }
                    }
                }
            }
            if showsPlanningAction, report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    CalendarPlanningButton { planningDestination.wrappedValue = .list }
                }
            }
        }
        .onChange(of: report.selectedYear) { zoom.cancel() }
        .onChange(of: presentation.mode) { model.setOverview(presentation.mode == .overview) }
        .onChange(of: stylesheet.calendar.overview.usesSpatialMotion) { zoom.cancel() }
        .onDisappear { zoom.cancel() }
    }

    private func restorePosition(_ initialTarget: CalendarPresentationState.Target?) {
        if let initialTarget {
            _detailPosition.initialize(id: initialTarget, anchor: .bottom)
            if let target = detailTarget, !presentation.isAvailable(target) {
                _detailPosition.scrollTo(id: initialTarget, anchor: .bottom)
            }
        }
        if presentation.mode == .detail, let target = detailTarget {
            // A new native scroll view must receive the command after its content mounts.
            _detailPosition.scrollTo(id: target, anchor: _detailPosition.anchor ?? .top)
        }
    }

    private func finishZoom(_ id: CalendarZoomTransitionState.ID) {
        guard zoom.finish(id) else { return }
        if presentation.mode == .detail {
            focusedTarget = detailTarget
        }
    }

    private func expand(_ target: CalendarPresentationState.Target) {
        guard presentation.expand(target) else { return }
        _detailPosition.scrollTo(id: target, anchor: .top)
    }

    private func toggleZoom() {
        switch presentation.mode {
            case .detail: presentation.mode = .overview
            case .overview:
                guard let target = detailTarget else { return }
                _ = presentation.expand(target)
        }
    }

    private func finishPinch(
        magnification: CGFloat,
        destination: CalendarPresentationState.Target?,
    ) {
        switch presentation.mode {
            case .detail:
                if magnification <= CalendarPresentationState
                    .overviewThreshold
                {
                    presentation.mode = .overview
                }
            case .overview:
                if magnification >= CalendarPresentationState.detailThreshold,
                   let destination
                {
                    expand(destination)
                }
        }
    }

    /// Hold the visible tiles while the destination lays out at the requested month.
    /// The overlay starts moving only after that scroll position has settled.
    private func changeZoom(_ intent: () -> Void) {
        guard zoom.phase == nil else { return }
        withTransaction(Transaction(animation: stylesheet.calendar.overview.usesSpatialMotion
                ? nil : stylesheet.calendar.overview.animation))
        {
            let previousMode = presentation.mode
            let source = zoom.measurement
            intent()
            guard presentation.mode != previousMode else { return }
            focusedTarget = nil
            if stylesheet.calendar.overview.usesSpatialMotion, let source,
               source.mode == previousMode
            {
                zoom.begin(
                    from: source,
                    to: presentation.mode,
                    focus: detailTarget,
                    alignment: _detailPosition.anchor ?? .top,
                )
            }
            zoom.updateMeasurement(nil)
            if presentation.mode == .overview {
                overviewPosition = ScrollPosition(
                    idType: CalendarPresentationState.Target.self,
                    edge: .top,
                )
            }
        }
    }

    private var calendarForecasts: [LocationForecast] {
        if let focusedRegion {
            return report.primaryRegionForecast(for: focusedRegion).map { [$0] } ?? []
        }
        return report.primaryRegionForecasts
    }
}

private struct CalendarUnavailableContent: View {
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .commonLoadErrorTitle), systemSymbol: .exclamationmarkIcloud)
        } description: {
            Text(description)
        }
    }
}

private struct CalendarZoomButton: View {
    let mode: CalendarPresentationState.Mode
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                mode == .detail ? String(localized: .calendarShowYear) :
                    String(localized: .calendarShowMonths),
                systemSymbol: mode == .detail ? .squareGrid3x3 : .rectangleGrid1x2,
            )
        }
        .disabled(disabled)
    }
}

private struct CalendarPlanningButton: View {
    let action: () -> Void

    var body: some View {
        Button(
            String(localized: .plannedStaysTitle),
            systemSymbol: .calendarBadgeClock,
            action: action,
        )
    }
}

#if DEBUG
    extension CalendarContentView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshotCases(awaitsLayout: false, focusesMonths: false)
        }

        static var measuredSnapshots: [SnapshotCase] {
            snapshotCases(awaitsLayout: true, focusesMonths: true, componentSettle: .immediate)
        }

        /// Mirrors the image subjects without splitting preview identities per configuration.
        fileprivate enum MonthPreviews: SnapshotProviding {
            static var snapshots: [SnapshotCase] {
                snapshotCases(awaitsLayout: false, focusesMonths: true)
            }
        }

        @SnapshotCaseBuilder
        private static func snapshotCases(
            awaitsLayout: Bool,
            focusesMonths: Bool,
            componentSettle: SnapshotSettle = .settled,
        ) -> [SnapshotCase] {
            let calendar = CalendarSnapshotCases(
                awaitsLayout: awaitsLayout,
                focusesMonths: focusesMonths,
            )
            if focusesMonths {
                calendar.snapshot(
                    name: "FullYear",
                    configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                ) { presentation in
                    NavigationStack {
                        CalendarContentView(
                            report: PreviewSupport.loadedYearReportModel(),
                            presentationState: presentation,
                        )
                    }
                }
            }
            whereSnapshot(
                name: "HistoryColumn",
                configurations: [SnapshotConfiguration(device: DuoLayoutSnapshotFixture
                        .historyColumn)],
            ) {
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.loadedYearReportModel(),
                        showsEstimateCard: false,
                    )
                }
            }
            whereSnapshot(
                name: "FlightAndEvidenceBadges",
                configurations: .componentRepresentative,
                measurementReadiness: .immediate,
                settle: componentSettle,
            ) {
                HStack {
                    ForEach([false, true], id: \.self) { isToday in
                        DayCell(
                            day: CalendarDayCell(
                                date: PreviewSupport.referenceNow,
                                dayOfMonth: 15,
                                regions: [],
                                isToday: isToday,
                                needsAttention: !isToday,
                                hasEvidence: true,
                                hasFlight: true,
                            ),
                            band: .none,
                            dateCalendar: Calendar(identifier: .gregorian),
                        )
                        .frame(width: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemBackground))
            }
            whereSnapshot(
                name: "MonthAccessibility",
                configurations: .componentRepresentative,
                // This standalone month receives its complete layout synchronously.
                measurementReadiness: .immediate,
                settle: componentSettle,
            ) {
                let calendar = Calendar(identifier: .gregorian)
                MonthGridView(
                    month: PreviewSupport.calendarAccessibilityMonth(calendar: calendar),
                    dateCalendar: calendar,
                    plannedPresence: { _ in nil },
                    planningSummary: [],
                )
                .padding()
                .background(Color(.systemBackground))
            }
            calendar.detail(
                name: "Flights",
                monthNumber: 7,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
                report: PreviewSupport.flightHistoryYearReportModel,
            )
            calendar.detail(
                name: "Itinerary",
                monthNumber: 10,
                configurations: .fullContentPhoneLightDark,
            ) { PreviewSupport.itineraryYearReportModel() }
            if focusesMonths {
                // October owns flexible arrival; November also exercises overlapping regions.
                calendar.detail(
                    name: "ItineraryOverlap",
                    monthNumber: 11,
                    configurations: .fullContentPhoneLightDark,
                ) { PreviewSupport.itineraryYearReportModel() }
            }
            calendar.detail(
                name: "WithData",
                monthNumber: 5,
                configurations: .fullContentScreenRepresentative,
                monthSettle: .immediate,
                report: PreviewSupport.loadedYearReportModel,
            )
            whereSnapshot(name: "InitialPosition", configurations: .phoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.loadedYearReportModel())
                }
            }
            calendar.detail(
                name: "Empty",
                monthNumber: 7,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
                report: PreviewSupport.emptyYearReportModel,
            )
            calendar.detail(
                name: "FutureWithoutPlans",
                monthNumber: 1,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
            ) {
                let base = PreviewSupport.loadedYearReportModel()
                let year = base.selectedYear + 1
                return YearReportModel(
                    services: base.services,
                    details: YearReportDetails(
                        primaryRegions: [.california, .newYork],
                        report: YearReport(year: year, days: [], totals: [:]),
                        primaryRegionLocations: [:],
                    ),
                    selectedYear: year,
                    preferences: base.preferences,
                    now: base.now,
                )
            }
            calendar.detail(
                name: "MissingDays",
                monthNumber: 1,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
                report: PreviewSupport.missingDaysYearReportModel,
            )
            // The Locations zoom destination keeps only the focused region's day markings.
            calendar.detail(
                name: "Focused",
                monthNumber: 5,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
                focusedRegion: .california,
                report: PreviewSupport.loadedYearReportModel,
            )
            calendar.detail(
                name: "FocusedPlannedStay",
                monthNumber: 7,
                configurations: .fullContentPhoneLightDark,
                focusedRegion: .newYork,
            ) { PreviewSupport.plannedStayYearReportModel() }
            calendar.detail(
                name: "MultiRegionPlannedStay",
                monthNumber: 7,
                configurations: .fullContentPhoneLightDark,
            ) { PreviewSupport.plannedStayYearReportModel(plannedRegion: .california) }
            // Overview retains its own matrix, including the large-type column adaptation.
            calendar.snapshot(
                name: "YearOverview",
                configurations: .fullContentScreenRepresentative,
                mode: .overview,
            ) { presentation in
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.loadedYearReportModel(),
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.snapshot(
                name: "YearOverviewPlannedStays",
                configurations: .fullContentPhoneLightDark,

                mode: .overview,
                includesThemes: true,
            ) { presentation in
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.itineraryYearReportModel(),
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.snapshot(
                name: "YearOverviewPastYear",
                configurations: .fullContentPhoneLightDark,

                mode: .overview,
            ) { presentation in
                let base = PreviewSupport.loadedYearReportModel()
                let referenceDate = CalendarDay(year: base.selectedYear + 1, month: 1, day: 1)
                    .startOfDay(in: base.calendar)
                let past = YearReportModel(
                    services: base.services,
                    details: YearReportDetails(
                        primaryRegions: [.california, .newYork],
                        report: PreviewSupport.sampleReport(),
                        primaryRegionLocations: [:],
                    ),
                    selectedYear: base.selectedYear,
                    preferences: base.preferences,
                    now: { referenceDate },
                )
                NavigationStack {
                    CalendarContentView(
                        report: past,
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.snapshot(
                name: "YearOverviewFocused",
                configurations: .fullContentPhoneLightDark,
                mode: .overview,
            ) { presentation in
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .newYork,
                        report: PreviewSupport.plannedStayYearReportModel(),
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.snapshot(
                name: "YearOverviewEmpty",
                configurations: .fullContentPhoneLightDark,
                mode: .overview,
            ) { presentation in
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.emptyYearReportModel(),
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.snapshot(
                name: "YearOverviewHiddenEstimates",
                configurations: .fullContentPhoneLightDark,

                mode: .overview,
            ) { presentation in
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport
                            .plannedStayYearReportModel(showsEstimatedTimeAndPlanning: false),
                        presentationState: presentation,
                        initialMode: .overview,
                    )
                }
            }
            calendar.detail(
                name: "PlannedStayHidden",
                monthNumber: 7,
                configurations: .fullContentPhoneLightDark,
                monthSettle: .immediate,
            ) {
                PreviewSupport.plannedStayYearReportModel(showsEstimatedTimeAndPlanning: false)
            }
        }
    }

    #Preview("Full-screen scenarios") {
        CalendarContentView.snapshotPreviews
    }

    #Preview("Snapshot subjects") {
        CalendarContentView.MonthPreviews.snapshotPreviews
    }
#endif

#if DEBUG
    extension CalendarContentView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            CalendarContentView.self,
            title: "Region Calendar",
        )

        static let yearFlyoverData = WhereFlyoverData.snapshots(
            CalendarContentView.self,
            id: WhereFlyoverScreenID(CalendarContentView.self, in: YearView.self),
            title: "Calendar",
        )
    }
#endif
