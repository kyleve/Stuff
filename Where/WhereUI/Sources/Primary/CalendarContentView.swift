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
    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel
    let showsPlanningToolbar: Bool
    let showsZoomToolbar: Bool

    @Environment(\.stylesheet) private var stylesheet
    @State private var monthsLoad: Result<[CalendarMonth], Error>?
    @State private var planningDestination: PlannedStaysDestination?
    @State private var presentation: CalendarPresentationModel
    @AccessibilityFocusState private var focusedTarget: CalendarPresentationModel.Target?
    @State private var zoom = CalendarZoomTransitionModel()
    @State private var scrollOffset = CGPoint.zero
    @State private var requestedZoomScroll: CalendarZoomTransitionModel.ID?

    /// A nil persistence key keeps zoom session-only, including in previews.
    init(
        focusedRegion: Region? = nil,
        report: YearReportModel,
        initialMode: CalendarPresentationModel.Mode = .detail,
        persistenceKey: CalendarZoomKey? = nil,
        showsPlanningToolbar: Bool = true,
        showsZoomToolbar: Bool = true,
    ) {
        self.focusedRegion = focusedRegion
        self.report = report
        self.showsPlanningToolbar = showsPlanningToolbar
        self.showsZoomToolbar = showsZoomToolbar
        _presentation = State(initialValue: CalendarPresentationModel(
            mode: initialMode,
            preferences: report.preferences,
            persistenceKey: persistenceKey,
        ))
    }

    @State private var scrollPosition = ScrollPosition(idType: CalendarPresentationModel.Target
        .self)

    private static let logger = WhereLog.session(CalendarViewLog.self)

    /// Inputs that invalidate a cached month grid.
    private struct CalendarLoadID: Equatable {
        let report: YearReport
        let missingDayKeys: Set<CalendarDay>
        let evidenceDayKeys: Set<CalendarDay>
        let flightDayKeys: Set<CalendarDay>
        let referenceDay: Date
        let focusedRegion: Region?
    }

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
                .task(id: calendarLoadID(report: yearReport)) {
                    zoom.cancel()
                    let result = loadCalendarMonths(from: yearReport)
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
        .sheet(item: $planningDestination) { destination in
            PlannedStaysDestinationView(destination: destination, report: report)
        }
        .toolbar {
            if showsZoomToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        changeZoom { presentation.toggle() }
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
            if showsPlanningToolbar, report.showsEstimatedTimeAndPlanning {
                PlannedStaysToolbar {
                    planningDestination = .list
                }
            }
        }
        .onChange(of: report.selectedYear) { zoom.cancel() }
        .onChange(of: stylesheet.calendar.overview.usesSpatialMotion) { zoom.cancel() }
        .onDisappear { zoom.cancel() }
    }

    private func calendarLoadID(report yearReport: YearReport) -> CalendarLoadID {
        CalendarLoadID(
            report: yearReport,
            missingDayKeys: report.missingDayKeys,
            evidenceDayKeys: report.evidenceDayKeys,
            flightDayKeys: report.flightDayKeys,
            referenceDay: report.calendar.startOfDay(for: report.referenceDate),
            focusedRegion: focusedRegion,
        )
    }

    private func loadCalendarMonths(from yearReport: YearReport) -> Result<[CalendarMonth], Error> {
        Result {
            try yearReport.calendarMonths(
                calendar: report.calendar,
                referenceDate: report.referenceDate,
                missingDates: report.missingDayKeys,
                evidenceDays: report.evidenceDayKeys,
                flightDays: report.flightDayKeys,
                focusedRegion: focusedRegion,
            )
        }
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
        let visibleMonths = CalendarPresentationModel.visibleMonths(
            months,
            report: report,
            focusedRegion: focusedRegion,
        )
        let currentMonth = months.first(where: \.isCurrentMonth)
        let estimateMonth = months.first(where: showsForecast(after:))
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
                                    planningAction: { planningDestination = .list },
                                )
                                .anchorPreference(key: CalendarZoomFrames.self, value: .bounds) {
                                    [.detail: [.tile(.estimate(monthKey(month))): $0]]
                                }
                                .id(CalendarPresentationModel.Target.estimate(monthKey(month)))
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
            .transformAnchorPreference(
                key: CalendarZoomFrames.self,
                value: .bounds,
            ) { frames, content in
                frames[overview ? .overview : .detail, default: [:]][.content] = content
            }
        }
        .id(presentation.mode)
        .transition(stylesheet.calendar.overview.transition)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(
                x: $0.contentOffset.x + $0.contentInsets.leading,
                y: $0.contentOffset.y + $0.contentInsets.top,
            )
        } action: { _, value in
            scrollOffset = value
        }
        .onScrollTargetVisibilityChange(idType: CalendarPresentationModel.Target.self) { targets in
            if zoom.phase == nil, scrollPosition.isPositionedByUser,
               let first = targets.first { presentation.remember(first) }
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
                presentation.finishPinch(
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
            availableMonths: visibleMonths.map(monthKey),
            estimateMonth: estimateMonth.map(monthKey),
        )) {
            guard !Task.isCancelled else { return }
            let isInitial = presentation.year == nil
            presentation.reconcile(
                year: report.selectedYear,
                availableMonths: visibleMonths.map(monthKey),
                currentMonth: currentMonth.map(monthKey),
                estimateMonth: estimateMonth.map(monthKey),
            )
            if !overview, let target = presentation.target {
                let initialTarget = isInitial ? estimateMonth
                    .map { CalendarPresentationModel.Target.estimate(monthKey($0)) } ?? target :
                    target
                if zoom.phase == nil {
                    scrollPosition.scrollTo(id: initialTarget, anchor: isInitial ? .bottom : .top)
                    if !isInitial { focusedTarget = target }
                }
            } else {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .overlayPreferenceValue(CalendarZoomFrames.self) { anchors in
            GeometryReader { proxy in
                let measured = CalendarZoomFrames.measure(
                    anchors[overview ? .overview : .detail] ?? [:],
                    in: proxy,
                    mode: overview ? .overview : .detail,
                    scrollOffset: scrollOffset,
                )
                Color.clear
                    .task(id: measured) {
                        guard !Task.isCancelled else { return }
                        zoom.updateMeasurement(measured)
                        if case let .preparing(source) = zoom.phase,
                           requestedZoomScroll != source.id,
                           let measured, measured.mode == .detail,
                           let target = presentation.target, measured.frames[target] != nil
                        {
                            requestedZoomScroll = source.id
                            scrollPosition.scrollTo(id: target, anchor: .top)
                        }
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
                    if presentation.mode == .detail { focusedTarget = presentation.target }
                })
                .background(stylesheet.calendar.overview.zoomBackground)
            }
        }
    }

    private struct CalendarLayoutID: Equatable {
        let year: Int
        let mode: CalendarPresentationModel.Mode
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
                zoom.begin(from: source, to: presentation.mode, focus: presentation.target)
            }
            zoom.updateMeasurement(nil)
            switch presentation.mode {
                case .overview:
                    scrollPosition = ScrollPosition(
                        idType: CalendarPresentationModel.Target.self,
                        edge: .top,
                    )
                case .detail:
                    if zoom.phase != nil {
                        scrollPosition = ScrollPosition(idType: CalendarPresentationModel.Target
                            .self)
                    } else if let target = presentation.target {
                        scrollPosition = ScrollPosition(id: target, anchor: .top)
                    }
            }
        }
    }

    @ViewBuilder
    private func zoomTile(
        _ target: CalendarPresentationModel.Target,
        mode: CalendarPresentationModel.Mode,
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
                    planningAction: mode == .detail ? { planningDestination = .list } : nil,
                )
        }
    }

    private func monthKey(_ month: CalendarMonth) -> CalendarDay {
        CalendarDay(year: month.year, month: month.month, day: 1)
    }

    private func target(for month: CalendarMonth) -> CalendarPresentationModel.Target {
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
        return Button { changeZoom { presentation.expand(destination) } } label: {
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
    }

    private func overviewEstimate(_ month: CalendarMonth) -> some View {
        let destination = CalendarPresentationModel.Target.estimate(monthKey(month))
        return Button { changeZoom { presentation.expand(destination) } } label: {
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
        report.showsEstimatedTimeAndPlanning
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

/// One month section: weekday header row, a day grid, and a footer tallying the
/// days spent in each region that month.
private struct MonthGridView: View {
    let month: CalendarMonth
    /// The region the calendar is focused on, if any — emphasized in the footer.
    var focusedRegion: Region?
    let dateCalendar: Calendar
    let plannedPresence: (CalendarDay) -> PlanningDayPresence?
    let planningSummary: [PlanningRegionSummary]
    var compact = false
    var isAvailable = true

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        compact ? stylesheet.calendar.compact : stylesheet.calendar
    }

    /// Resolve the month variant once so its background and inherited text
    /// treatment cannot drift apart.
    private var card: WhereStylesheet.CalendarStyle.MonthStyle.Card {
        month.isCurrentMonth ? calendar.month.current : calendar.month.plain
    }

    /// Shared by the fill and border so every month uses the same continuous
    /// corner geometry.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: calendar.month.cornerRadius, style: .continuous)
    }

    private var weekdaySymbols: [String] {
        guard compact else { return month.weekdaySymbols }
        let symbols = dateCalendar.veryShortStandaloneWeekdaySymbols
        let offset = dateCalendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthName: String {
        month.startOfMonth.formatted(.dateTime.month(.wide))
    }

    private var accessibility: CalendarMonthAccessibility {
        CalendarMonthAccessibility(
            month: month,
            calendar: dateCalendar,
            memberships: memberships(for:),
            planningSummary: planningSummary
                .filter { focusedRegion == nil || $0.region == focusedRegion },
        )
    }

    var body: some View {
        let monthAccessibility = accessibility

        VStack(alignment: .leading, spacing: calendar.month.sectionSpacing) {
            Text(monthName)
                .font(compact ? .system(size: calendar.overview.titleFontSize, weight: .semibold) :
                    .title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isAvailable ? card.foreground : calendar.overview
                    .unavailableForeground)

            dayGrid

            if !compact, !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
            ForEach(
                (compact ? [] : planningSummary)
                    .filter { focusedRegion == nil || $0.region == focusedRegion },
                id: \.region,
            ) { summary in
                VStack(alignment: .leading, spacing: calendar.month.footerSpacing) {
                    if summary.plannedDays.upper > 0 {
                        planningSummaryRow(
                            region: summary.region,
                            days: summary.plannedDays,
                            kind: summary.plannedDays.isExact
                                ? .planningCalendarPlanned : .planningCalendarPossible,
                            symbol: summary.plannedDays.isExact ? .lineDiagonal : .circleDashed,
                        )
                    }
                    if summary.homeDays.upper > 0 {
                        planningSummaryRow(
                            region: summary.region,
                            days: summary.homeDays,
                            kind: .planningCalendarHome,
                            symbol: .house,
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(calendar.month.padding)
        .foregroundStyle(card.foreground)
        .background {
            // Transparent month cards share the screen background. The current
            // month stands out through its accent text and heavier border.
            cardShape
                .fill(card.fill)
                .overlay {
                    cardShape.strokeBorder(card.border, lineWidth: card.borderWidth)
                }
        }
        .contentShape(cardShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monthAccessibility.label)
        .accessibilityValue(monthAccessibility.value)
    }

    /// A month has at most six weeks. Eager rows keep its intrinsic height exact
    /// while a zoom destination is offscreen or covered by the transition overlay.
    private var dayGrid: some View {
        let weekCount = compact ? 6 :
            (month.leadingBlankCount + month.days.count + month.weekdayCount - 1) / month
            .weekdayCount
        return Grid(
            horizontalSpacing: calendar.month.gridSpacing,
            verticalSpacing: calendar.month.gridSpacing,
        ) {
            GridRow {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: calendar.month.weekdayFontSize))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0 ..< weekCount, id: \.self) { week in
                GridRow {
                    ForEach(0 ..< month.weekdayCount, id: \.self) { weekday in
                        let index = week * month.weekdayCount + weekday - month.leadingBlankCount
                        if month.days.indices.contains(index) {
                            DayCell(
                                day: month.days[index],
                                band: bandGeometry(at: index),
                                dateCalendar: dateCalendar,
                                compact: compact,
                                isAvailable: isAvailable,
                            )
                        } else {
                            Color.clear
                                .frame(height: calendar.day.minHeight)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planningSummaryRow(
        region: Region,
        days: DayBounds,
        kind: LocalizedStringResource,
        symbol: SFSymbol,
    ) -> some View {
        let title = String(localized: .planningCalendarMonthSummary(
            region.localizedName,
            String(localized: kind),
        ))
        if calendar.month.stacksFooter {
            VStack(alignment: .leading, spacing: calendar.month.footerSpacing) {
                Label(title, systemSymbol: symbol)
                    .fixedSize(horizontal: false, vertical: true)
                Text(WhereFormat.dayCount(days))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent {
                Text(WhereFormat.dayCount(days))
            } label: {
                Label(title, systemSymbol: symbol)
            }
        }
    }

    /// The stay-pill geometry for the day at `index`: a run is contiguous days
    /// with the identical region set, so its true ends round fully while a run
    /// spilling across a week boundary rounds subtly (and same-row neighbours
    /// extend half the grid gap so the pill reads as one connected shape).
    private func bandGeometry(at index: Int) -> DayBandGeometry {
        let days = month.days
        let day = days[index]
        let regions = displayedRegions(for: day)
        guard !regions.isEmpty else { return .none }

        let regionSet = Set(regions)
        let projected = memberships(for: day)
        let column = (month.leadingBlankCount + index) % month.weekdayCount
        let isRowStart = column == 0
        let isRowEnd = column == month.weekdayCount - 1
        let joinsLeft = index > 0
            && Set(displayedRegions(for: days[index - 1])) == regionSet
            && memberships(for: days[index - 1]) == projected
        let joinsRight = index < days.count - 1
            && Set(displayedRegions(for: days[index + 1])) == regionSet
            && memberships(for: days[index + 1]) == projected

        let band = calendar.regionBand
        let halfGap = calendar.month.gridSpacing / 2
        return DayBandGeometry(
            regions: regions,
            memberships: projected,
            column: column,
            leadingRadius: joinsLeft ? (isRowStart ? band.continuationRadius : 0) : band
                .cornerRadius,
            trailingRadius: joinsRight ? (isRowEnd ? band.continuationRadius : 0) : band
                .cornerRadius,
            extendLeading: joinsLeft && !isRowStart ? halfGap : 0,
            extendTrailing: joinsRight && !isRowEnd ? halfGap : 0,
        )
    }

    private func displayedRegions(for day: CalendarDayCell) -> [Region] {
        Region.inCanonicalOrder(Set(day.regions).union(memberships(for: day).keys))
    }

    private func memberships(for day: CalendarDayCell) -> [Region: PlanningDayPresence.Membership] {
        let key = CalendarDay(from: day.date, in: dateCalendar)
        guard let presence = plannedPresence(key) else { return [:] }
        var regions = presence.possibleRegions
        if let home = presence.homeAssumption { regions.insert(home.region) }
        if let focusedRegion { regions = regions.intersection([focusedRegion]) }
        return Dictionary(uniqueKeysWithValues: regions.compactMap { region in
            presence.membership(in: region).map { (region, $0) }
        })
    }
}

/// How to draw a day's slice of the region "stay" pill: which corners round
/// (the run's ends) and how far to bleed into the grid gaps so a run reads as
/// one connected shape. Empty `regions` means no pill.
private struct DayBandGeometry {
    var regions: [Region]
    var memberships: [Region: PlanningDayPresence.Membership]
    var isPlanned: Bool {
        !memberships.isEmpty
    }

    var hasPossible: Bool {
        memberships.values.contains { membership in
            switch membership {
                case .planned(.possible), .homeAssumed(.possible): true
                case .planned(.certain), .homeAssumed(.certain): false
            }
        }
    }

    var column: Int
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var extendLeading: CGFloat
    var extendTrailing: CGFloat

    static let none = DayBandGeometry(
        regions: [],
        memberships: [:],
        column: 0,
        leadingRadius: 0,
        trailingRadius: 0,
        extendLeading: 0,
        extendTrailing: 0,
    )
}

/// The per-month footer: one row per region present that month, showing its dot
/// color and how many days were spent there. The focused region (if any) is
/// emphasized so it stands out from the surrounding context rows.
private struct MonthFooter: View {
    let totals: [RegionDayTally]
    var focusedRegion: Region?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.month.footerSpacing) {
            Divider()
                .padding(.bottom, calendar.month.footerDividerSpacing)
            ForEach(totals) { tally in
                row(for: tally)
            }
        }
    }

    private func row(for tally: RegionDayTally) -> some View {
        let isFocused = tally.region == focusedRegion
        let layout = calendar.month.stacksFooter
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: calendar.month.footerRowSpacing))
            : AnyLayout(HStackLayout(spacing: calendar.month.footerRowSpacing))
        return layout {
            HStack(spacing: calendar.month.footerRowSpacing) {
                Circle()
                    .fill(regionStyles.style(for: tally.region).tint)
                    .frame(
                        width: calendar.dotSize,
                        height: calendar.dotSize,
                    )
                Text(tally.region.localizedName)
                    .font(.subheadline)
                    .fontWeight(isFocused ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !calendar.month.stacksFooter {
                Spacer(minLength: 0)
            }
            Text(WhereFormat.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
    }
}

/// One day in the month grid: the day number, region-presence dots beneath it,
/// and a subtle region-tinted "stay" pill behind it that connects to adjacent
/// days in the same run so a stretch in one place reads as a single shape.
private struct DayCell: View {
    let day: CalendarDayCell
    /// The stay-pill slice for this day (computed by the enclosing month).
    let band: DayBandGeometry
    let dateCalendar: Calendar
    var compact = false
    var isAvailable = true

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        compact ? stylesheet.calendar.compact : stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.day.numberDotSpacing) {
            Text("\(day.dayOfMonth)")
                .font(.system(size: calendar.day.numberFontSize))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(dayNumberColor)
                .frame(
                    width: compact ? nil : calendar.day.numberSize,
                    height: calendar.day.numberSize,
                )
                .background {
                    if day.isToday {
                        Circle()
                            .fill(calendar.day.todayMarker)
                    } else if day.needsAttention {
                        Circle()
                            .fill(calendar.day.unresolvedMarker)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !compact, day.hasEvidence || day.hasFlight {
                        HStack(spacing: calendar.day.badge.iconSpacing) {
                            if day.hasEvidence {
                                badgeIcon(.paperclip)
                            }
                            if day.hasFlight {
                                badgeIcon(.airplane)
                            }
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(calendar.day.badge.padding)
                        .background(Capsule().fill(Color(.systemBackground)))
                        // Keep the first icon at the corner; additional icons
                        // extend to the right without covering the day number.
                        .offset(badgeOffset)
                    }
                }

            dots
        }
        // Pad the content, then back it with the pill so the pill hugs the
        // content with a little vertical breathing room (rather than butting
        // into the dots); the outer frame is the tap target.
        .frame(maxWidth: .infinity)
        .padding(.vertical, calendar.regionBand.verticalInset)
        .background { stayPill }
        .frame(minHeight: calendar.day.minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(Date.FormatStyle(
            date: .complete,
            time: .omitted,
            calendar: dateCalendar,
            timeZone: dateCalendar.timeZone,
        )))
        .accessibilityValue(accessibilitySummary)
    }

    private var badgeOffset: CGSize {
        let extraWidth = day.hasEvidence && day.hasFlight
            ? calendar.day.badge.iconSize + calendar.day.badge.iconSpacing
            : 0
        return CGSize(
            width: calendar.day.badge.offset.width + extraWidth,
            height: calendar.day.badge.offset.height,
        )
    }

    private func badgeIcon(_ symbol: SFSymbol) -> some View {
        Image(systemSymbol: symbol)
            .font(.system(size: calendar.day.badge.iconSize, weight: .bold))
            .frame(width: calendar.day.badge.iconSize, height: calendar.day.badge.iconSize)
    }

    private var accessibilitySummary: String {
        var values = band.regions.map { region in
            guard let membership = band.memberships[region] else { return region.localizedName }
            return String(localized: .planningCalendarMonthSummary(
                region.localizedName,
                WhereFormat.planningMembership(membership),
            ))
        }
        if day.hasEvidence { values.append(String(localized: .calendarAttachmentAccessibility)) }
        if day.hasFlight { values.append(String(localized: .historyFlight)) }
        return values.joined(separator: "; ")
    }

    /// Region-presence dots beneath the day number (one per region the day
    /// counts for), each with a subtle background-colored rim. On a multi-region
    /// day the dots overlap into a cluster, the rims keeping them distinct.
    /// Empty days keep the row height so the grid baseline is even.
    private var dots: some View {
        let isCluster = band.regions.count > 1
        return HStack(spacing: isCluster ? -calendar.day.dotOverlap : calendar.day.contentSpacing) {
            ForEach(band.regions, id: \.self) { region in
                Group {
                    switch band.memberships[region] {
                        case .homeAssumed:
                            Image(systemSymbol: .houseFill)
                                .resizable()
                                .scaledToFit()
                        case .planned(.possible):
                            Circle().strokeBorder(lineWidth: calendar.day.dotStrokeWidth)
                        case .planned(.certain), nil:
                            Circle()
                    }
                }
                .foregroundStyle(regionStyles.style(for: region).tint)
                .frame(width: calendar.day.dotSize, height: calendar.day.dotSize)
            }
        }
        .frame(height: calendar.day.dotSize)
    }

    /// The subtle region-tinted pill spanning this day's slice of a stay run —
    /// tinted per region (a soft blend on multi-region days), its corners
    /// rounded per `band`, inset vertically, and bled `extend…` points into the
    /// grid gaps so same-run neighbours join into one shape. A `GeometryReader`
    /// gives the exact cell size to size and offset the overflow precisely.
    @ViewBuilder
    private var stayPill: some View {
        if !band.regions.isEmpty {
            GeometryReader { proxy in
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: band.leadingRadius,
                    bottomLeadingRadius: band.leadingRadius,
                    bottomTrailingRadius: band.trailingRadius,
                    topTrailingRadius: band.trailingRadius,
                )
                ZStack {
                    shape
                        .fill(pillFill)
                        .opacity(
                            band.isPlanned
                                ? calendar.regionBand.planned.fillOpacity
                                : calendar.regionBand.opacity,
                        )
                    if band.isPlanned {
                        PlannedStayHatch(
                            color: band.regions
                                .first
                                .map { regionStyles.style(for: $0).tint } ?? .accentColor,
                            spacing: calendar.regionBand.planned.hatchSpacing,
                            lineWidth: calendar.regionBand.planned.hatchLineWidth,
                            gridOriginX: CGFloat(band.column)
                                * (proxy.size.width + calendar.month.gridSpacing)
                                - band.extendLeading,
                        )
                        .opacity(calendar.regionBand.planned.hatchOpacity)
                        .clipShape(shape)
                    }
                    if band.hasPossible {
                        shape.strokeBorder(
                            band.regions.first
                                .map { regionStyles.style(for: $0).tint } ?? .accentColor,
                            style: StrokeStyle(
                                lineWidth: calendar.regionBand.planned.hatchLineWidth,
                                dash: [calendar.regionBand.planned.hatchSpacing],
                            ),
                        )
                    }
                }
                .frame(
                    width: proxy.size.width + band.extendLeading + band.extendTrailing,
                    height: proxy.size.height,
                )
                .offset(x: -band.extendLeading)
            }
        }
    }

    /// The pill's tint: one region reads as a solid wash; a multi-region day
    /// (rare — a travel day) softly blends its regions left-to-right.
    private var pillFill: LinearGradient {
        LinearGradient(
            colors: band.regions.map { regionStyles.style(for: $0).tint },
            startPoint: .leading,
            endPoint: .trailing,
        )
    }

    private var dayNumberColor: Color {
        if day.isToday {
            calendar.day.todayNumberColor
        } else if day.needsAttention {
            calendar.day.unresolvedNumberColor
        } else {
            isAvailable ? .primary : calendar.overview.unavailableForeground
        }
    }
}

#if DEBUG
    extension CalendarContentView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "FlightAndEvidenceBadges",
                configurations: .componentDefaults,
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
            whereSnapshot(name: "MonthAccessibility", configurations: .componentDefaults) {
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
            whereSnapshot(name: "Flights", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport
                        .flightHistoryYearReportModel())
                }
            }
            whereSnapshot(name: "Itinerary", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    CalendarContentView(report: PreviewSupport.itineraryYearReportModel())
                }
            }
            whereSnapshot(name: "WithData", configurations: .fullContentScreenDefaults) {
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
            whereSnapshot(name: "YearOverview", configurations: .fullContentScreenDefaults) {
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
