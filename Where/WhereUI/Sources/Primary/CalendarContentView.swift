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
                            calendarContent(months: months)
                        case let .failure(error):
                            calendarLayoutError(error)
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
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(error.message)
                }
            } else {
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(String(localized: .calendarUnavailableDescription))
                }
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
                    Button {
                        changeZoom { toggleZoom() }
                    } label: {
                        Label(
                            presentation
                                .mode == .detail ? String(localized: .calendarShowYear) :
                                String(localized: .calendarShowMonths),
                            systemSymbol: presentation
                                .mode == .detail ? .squareGrid3x3 : .rectangleGrid1x2,
                        )
                    }
                    .disabled(monthsLoad == nil || zoom.phase != nil)
                }
            }
            if showsPlanningAction, report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        planningDestination.wrappedValue = .list
                    }
                }
            }
        }
        .onChange(of: report.selectedYear) { zoom.cancel() }
        .onChange(of: presentation.mode) { model.setOverview(presentation.mode == .overview) }
        .onChange(of: stylesheet.calendar.overview.usesSpatialMotion) { zoom.cancel() }
        .onDisappear { zoom.cancel() }
    }

    private func calendarLayoutError(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(String(localized: .commonLoadErrorTitle), systemSymbol: .exclamationmarkIcloud)
        } description: {
            Text(String(localized: .calendarUnavailableDescription))
        }
        .onAppear {
            Self.logger.layoutFailed(
                error: .restricted(.errorDetails, error),
            )
        }
    }

    private func calendarContent(months: [CalendarMonth]) -> some View {
        let availableMonths = CalendarModel.visibleMonths(
            months,
            report: report,
            focusedRegion: focusedRegion,
        )
        let currentMonth = months.first(where: \.isCurrentMonth)
        let estimateMonth = months.first(where: showsForecast(after:))
        let visibleMonths = availableMonths
        let overview = presentation.mode == .overview

        return ScrollView {
            Group {
                if overview {
                    VStack(spacing: stylesheet.calendar.monthSpacing) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(
                                .flexible(),
                                spacing: stylesheet.calendar.overview.spacing,
                            ), count: stylesheet.calendar.overview.columns),
                            spacing: stylesheet.calendar.overview.spacing,
                        ) {
                            ForEach(months) { month in
                                overviewMonth(
                                    month,
                                    available: visibleMonths.contains(where: { $0.id == month.id }),
                                )
                            }
                        }
                        if let estimateMonth {
                            overviewEstimate(estimateMonth)
                        }
                    }
                } else {
                    VStack(spacing: stylesheet.calendar.monthSpacing) {
                        ForEach(visibleMonths) { month in
                            monthView(month, compact: false)
                                .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
                                    [.detail: [.tile(target(for: month)): $0]]
                                }
                                .id(target(for: month))
                                .accessibilityFocused($focusedTarget, equals: target(for: month))
                            if showsForecast(after: month) {
                                LocationForecastPanel(
                                    forecasts: calendarForecasts,
                                    microprintRegions: report.ranking.primary.map(\.region),
                                    homeRegion: report.forecasts.planning.homeRegion,
                                    planningAction: { planningDestination.wrappedValue = .list },
                                )
                                .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
                                    [.detail: [.tile(.estimate(monthKey(month))): $0]]
                                }
                                .id(CalendarPresentationState.Target.estimate(monthKey(month)))
                                .accessibilityFocused(
                                    $focusedTarget,
                                    equals: .estimate(monthKey(month)),
                                )
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .padding()
            .whereContentRoot()
            // Keep the content origin at the full scroll width so zoom measurements
            // retain the centered column's horizontal offset.
            .transformAnchorPreference(
                key: CalendarZoomFrames.self,
                value: .bounds,
            ) { frames, content in
                frames[overview ? .overview : .detail, default: [:]][.content] = content
            }
        }
        // Each mode keeps its own binding while outgoing content finishes its transition.
        .scrollPosition(calendarPosition)
        .id(presentation.mode)
        .transition(stylesheet.calendar.overview.transition)
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(
                x: $0.contentOffset.x + $0.contentInsets.leading,
                y: $0.contentOffset.y + $0.contentInsets.top,
            )
        } action: { _, value in
            scrollOffset = value
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            let viewportSize = zoom.measurement?.viewport.size ?? .zero
            let point = CGPoint(
                x: value.startAnchor.x * viewportSize.width,
                y: value.startAnchor.y * viewportSize.height,
            )
            let destination = (zoom.measurement?.frames ?? [:])
                .first(where: {
                    $0.key.month.year == report.selectedYear && $0.value.contains(point)
                })?.key
            changeZoom {
                finishPinch(
                    magnification: value.magnification,
                    destination: destination,
                )
            }
        })
        .sensoryFeedback(.impact(weight: .light), trigger: presentation.rejectionTrigger)
        .onChange(of: presentation.rejectionTrigger) {
            AccessibilityNotification.Announcement(String(localized: .calendarMonthUnavailable))
                .post()
        }
        .task(id: CalendarLayoutID(
            year: report.selectedYear,
            mode: presentation.mode,
            availableMonths: availableMonths.map(monthKey),
            estimateMonth: estimateMonth.map(monthKey),
        )) {
            guard !Task.isCancelled else { return }
            presentation.reconcile(
                year: report.selectedYear,
                availableMonths: availableMonths.map(monthKey),
                estimateMonth: estimateMonth.map(monthKey),
            )
            let initialTarget = estimateMonth
                .map { CalendarPresentationState.Target.estimate(monthKey($0)) }
                ?? (currentMonth ?? availableMonths.last)
                .map { CalendarPresentationState.Target.month(monthKey($0)) }
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
        // Hide the live tiles while their copies move, leaving the page background visible.
        .opacity(zoom.phase == nil ? 1 : 0)
        .overlayPreferenceValue(CalendarZoomFrames.self) { anchors in
            let canReveal = onPresentationReady != nil && presentation.year == report.selectedYear
            Color.clear
                .onGeometryChange(for: CalendarZoomTransitionState.Measurement?.self) { proxy in
                    CalendarZoomFrames.measure(
                        anchors[overview ? .overview : .detail] ?? [:],
                        in: proxy,
                        mode: overview ? .overview : .detail,
                        scrollOffset: scrollOffset,
                    )
                } action: { value in
                    zoom.updateMeasurement(value)
                }
                .onGeometryChange(for: Bool.self) { proxy in
                    canReveal && proxy.size.width > 0 && proxy.size.height > 0
                } action: { isReady in
                    if isReady {
                        onPresentationReady?()
                    }
                }
                .allowsHitTesting(false)
        }
        .allowsHitTesting(zoom.phase == nil)
        .accessibilityHidden(zoom.phase != nil)
        .overlay {
            if let phase = zoom.phase {
                CalendarZoomOverlay(phase: phase, content: { target, mode in
                    zoomTile(target, mode: mode, months: months)
                }, completion: { id in
                    guard zoom.finish(id) else { return }
                    if presentation.mode == .detail {
                        focusedTarget = detailTarget
                    }
                })
            }
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

    private struct CalendarLayoutID: Equatable {
        let year: Int
        let mode: CalendarPresentationState.Mode
        let availableMonths: [CalendarDay]
        let estimateMonth: CalendarDay?
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

    @ViewBuilder
    private func zoomTile(
        _ target: CalendarPresentationState.Target,
        mode: CalendarPresentationState.Mode,
        months: [CalendarMonth],
    ) -> some View {
        switch target {
            case let .month(day):
                if let month = months.first(where: { monthKey($0) == day }) {
                    monthView(
                        month,
                        compact: mode == .overview,
                        isAvailable: presentation.isAvailable(target),
                    )
                }
            case .estimate:
                LocationForecastPanel(
                    forecasts: calendarForecasts,
                    microprintRegions: report.ranking.primary.map(\.region),
                    homeRegion: report.forecasts.planning.homeRegion,
                    planningAction: mode == .detail ? { planningDestination.wrappedValue = .list } :
                        nil,
                )
        }
    }

    private func monthKey(_ month: CalendarMonth) -> CalendarDay {
        CalendarDay(year: month.year, month: month.month, day: 1)
    }

    private func target(for month: CalendarMonth) -> CalendarPresentationState.Target {
        .month(monthKey(month))
    }

    private func monthView(
        _ month: CalendarMonth,
        compact: Bool,
        isAvailable: Bool = true,
    ) -> some View {
        MonthGridView(
            month: month,
            focusedRegion: focusedRegion,
            report: report,
            compact: compact,
            isAvailable: isAvailable,
        )
    }

    private func overviewMonth(_ month: CalendarMonth, available: Bool) -> some View {
        let destination = target(for: month)
        return Button { changeZoom { expand(destination) } } label: {
            monthView(month, compact: true, isAvailable: available)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
            [.overview: [.tile(destination): $0]]
        }
        .accessibilityHint(available ? String(localized: .calendarExpandMonth) :
            String(localized: .calendarMonthUnavailable))
        .modifier(CalendarOverviewFeedback(
            rejected: presentation.rejectedTarget == destination,
            trigger: presentation.rejectionTrigger,
        ))
    }

    private func overviewEstimate(_ month: CalendarMonth) -> some View {
        let destination = CalendarPresentationState.Target.estimate(monthKey(month))
        return Button { changeZoom { expand(destination) } } label: {
            LocationForecastPanel(
                forecasts: calendarForecasts,
                microprintRegions: report.ranking.primary.map(\.region),
                homeRegion: report.forecasts.planning.homeRegion,
            )
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
            [.overview: [.tile(destination): $0]]
        }
        .accessibilityHint(String(localized: .calendarExpandEstimate))
    }

    private func showsForecast(after month: CalendarMonth) -> Bool {
        showsEstimateCard && report.showsEstimatedTimeAndPlanning
            && month.isCurrentMonth
            && !calendarForecasts.isEmpty
    }

    private var calendarForecasts: [LocationForecast] {
        if let focusedRegion {
            return report.forecasts.forecast(for: focusedRegion, report: report.report).map { [$0] }
                ?? []
        }
        return report.forecasts.leadingForecasts(report: report.report)
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
