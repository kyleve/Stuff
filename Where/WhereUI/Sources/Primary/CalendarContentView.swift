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
    enum ScrollRole: Hashable { case detail }
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
        presentationState: CalendarPresentationState? = nil,
        initialMode: CalendarPresentationState.Mode = .detail,
        persistenceKey: CalendarZoomKey? = nil,
        scrollRole: some Hashable = ScrollRole.detail,
        planningDestination: Binding<PlannedStaysDestination?>? = nil,
    ) {
        self.focusedRegion = focusedRegion
        self.report = report
        self.showsEstimateCard = showsEstimateCard
        self.showsPlanningAction = showsPlanningAction
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
        .whereThemeScreen(.year)
        .whereThemeActivity(planningDestination.wrappedValue == nil)
        .modifier(PlanningPresentation(
            report: report,
            destination: planningDestination,
            isEnabled: suppliedPlanningDestination == nil,
        ))
        .toolbar {
            Group {
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
                                .whereThemeArtworkSpace(.calendarMonth)
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
                                .whereThemeArtworkSpace(.forecastPanel)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .padding()
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
        .sensoryFeedback(.impact(weight: .light), trigger: presentation.rejectionCount)
        .onChange(of: presentation.rejectionCount) {
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
        .overlayPreferenceValue(CalendarZoomFrames.self) { anchors in
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
                    if presentation.mode == .detail { focusedTarget = detailTarget }
                })
                .background(stylesheet.calendar.overview.zoomBackground)
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
                    .overviewThreshold { presentation.mode = .overview }
            case .overview:
                if magnification >= CalendarPresentationState.detailThreshold,
                   let destination { expand(destination) }
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
            dateCalendar: report.calendar,
            plannedPresence: displayedPlannedPresence(on:),
            planningSummary: report.showsEstimatedTimeAndPlanning ? report.forecasts
                .plannedRegionSummaries(in: month) : [],
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
            trigger: presentation.rejectionCount,
        ))
        .whereThemeArtworkSpace(.calendarMonth)
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
        .whereThemeArtworkSpace(.forecastPanel)
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

    private func displayedPlannedPresence(on day: CalendarDay) -> PlanningDayPresence? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return report.forecasts.plannedPresence(on: day)
    }
}

#if DEBUG
    extension CalendarContentView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
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
            whereSnapshot(name: "MonthAccessibility", configurations: .componentRepresentative) {
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
            whereSnapshot(name: "Flights", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport
                        .flightHistoryYearReportModel())
                }
            }
            whereSnapshot(name: "Itinerary", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.itineraryYearReportModel())
                }
            }
            whereSnapshot(name: "WithData", configurations: .fullContentScreenRepresentative) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.loadedYearReportModel())
                }
            }
            whereSnapshot(name: "InitialPosition", configurations: .phoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.loadedYearReportModel())
                }
            }
            whereSnapshot(name: "Empty", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.emptyYearReportModel())
                }
            }
            whereSnapshot(name: "FutureWithoutPlans", configurations: .fullContentPhoneLightDark) {
                let base = PreviewSupport.loadedYearReportModel()
                let year = base.selectedYear + 1
                let future = YearReportModel(
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
                NavigationStack {
                    CalendarContentView(report: future)
                }
            }
            whereSnapshot(name: "MissingDays", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.missingDaysYearReportModel())
                }
            }
            // The Locations tab's zoom destination: one region's days only.
            whereSnapshot(name: "Focused", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .california,
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
            whereSnapshot(name: "FocusedPlannedStay", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .newYork,
                        report: PreviewSupport.plannedStayYearReportModel(),
                    )
                }
            }
            whereSnapshot(
                name: "MultiRegionPlannedStay",
                configurations: .fullContentPhoneLightDark,
            ) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.plannedStayYearReportModel())
                }
            }
            // Overview is a distinct layout and retains its full matrix alongside WithData.
            whereSnapshot(name: "YearOverview", configurations: .fullContentScreenRepresentative) {
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.loadedYearReportModel(),
                        initialMode: .overview,
                    )
                }
            }
            whereThemeSnapshot(
                name: "YearOverviewPlannedStays",
                configurations: .fullContentPhoneLightDark,
            ) {
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.itineraryYearReportModel(),
                        initialMode: .overview,
                    )
                }
            }
            whereSnapshot(
                name: "YearOverviewPastYear",
                configurations: .fullContentPhoneLightDark,
            ) {
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
                    CalendarContentView(report: past, initialMode: .overview)
                }
            }
            whereSnapshot(name: "YearOverviewFocused", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        focusedRegion: .newYork,
                        report: PreviewSupport.plannedStayYearReportModel(),
                        initialMode: .overview,
                    )
                }
            }
            whereSnapshot(name: "YearOverviewEmpty", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport.emptyYearReportModel(),
                        initialMode: .overview,
                    )
                }
            }
            whereSnapshot(
                name: "YearOverviewHiddenEstimates",
                configurations: .fullContentPhoneLightDark,
            ) {
                NavigationStack {
                    CalendarContentView(
                        report: PreviewSupport
                            .plannedStayYearReportModel(showsEstimatedTimeAndPlanning: false),
                        initialMode: .overview,
                    )
                }
            }
            whereSnapshot(
                name: "PlannedStayHidden",
                configurations: .fullContentPhoneLightDark,
            ) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.plannedStayYearReportModel(
                        showsEstimatedTimeAndPlanning: false,
                    ))
                }
            }
        }
    }

    #Preview {
        CalendarContentView.snapshotPreviews
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
