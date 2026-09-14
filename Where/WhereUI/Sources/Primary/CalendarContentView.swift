import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

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

    @Environment(\.stylesheet) private var stylesheet
    @State private var monthsLoad: Result<[CalendarMonth], Error>?
    @State private var planningDestination: PlannedStaysDestination?
    @State private var initiallyPositionedYear: Int?
    @State private var scrollPosition = ScrollPosition(idType: String.self)

    private static let logger = WhereLog.session(CalendarViewLog.self)

    /// Inputs that invalidate a cached month grid.
    private struct CalendarLoadID: Equatable {
        let report: YearReport
        let missingDayKeys: Set<CalendarDay>
        let evidenceDayKeys: Set<CalendarDay>
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
                    Self.logger {
                        .openedWithoutReport(loadState: String(describing: report.loadState))
                    }
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
            if report.showsEstimatedTimeAndPlanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        String(localized: .plannedStaysTitle),
                        systemSymbol: .calendarBadgeClock,
                    ) {
                        planningDestination = .list
                    }
                }
            }
        }
    }

    private func calendarLoadID(report yearReport: YearReport) -> CalendarLoadID {
        CalendarLoadID(
            report: yearReport,
            missingDayKeys: report.missingDayKeys,
            evidenceDayKeys: report.evidenceDayKeys,
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
            Self.logger { .layoutFailed(description: String(describing: error)) }
        }
    }

    private func calendarContent(months: [CalendarMonth]) -> some View {
        let visibleMonths = shownMonths(months)
        let initialMonthID = visibleMonths.first(where: \.isCurrentMonth)?.id
            ?? visibleMonths.last?.id

        return ScrollView {
            LazyVStack(spacing: stylesheet.calendar.monthSpacing) {
                ForEach(visibleMonths) { month in
                    VStack(spacing: stylesheet.calendar.monthSpacing) {
                        MonthGridView(
                            month: month,
                            focusedRegion: focusedRegion,
                            dateCalendar: report.calendar,
                            plannedPresence: displayedPlannedPresence(on:),
                            planningSummary: report.showsEstimatedTimeAndPlanning
                                ? report.forecasts.plannedRegionSummaries(in: month) : [],
                        )

                        // In chronological flow, the estimate belongs immediately
                        // after the month whose recorded pace it is projecting from.
                        if showsForecast(after: month) {
                            LocationForecastPanel(
                                forecasts: calendarForecasts,
                                microprintRegions: report.ranking.primary.map(\.region),
                                homeRegion: report.forecasts.planning.homeRegion,
                                planningAction: { planningDestination = .list },
                            )
                        }
                    }
                    .id(month.id)
                }
            }
            .scrollTargetLayout()
            .padding()
        }
        .scrollPosition($scrollPosition)
        .task(id: report.selectedYear) {
            guard initiallyPositionedYear != report.selectedYear else { return }
            guard let initialMonthID else { return }
            scrollPosition.scrollTo(id: initialMonthID, anchor: .bottom)
            initiallyPositionedYear = report.selectedYear
        }
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

    /// The months to show in chronological order. Future months are omitted
    /// unless a planned stay reaches into them; a past year shows the full year.
    private func shownMonths(_ months: [CalendarMonth]) -> [CalendarMonth] {
        guard
            let currentMonthStart = report.calendar
            .dateInterval(of: .month, for: report.referenceDate)?
            .start
        else {
            return months
        }
        let lastPlannedDay = report.showsEstimatedTimeAndPlanning
            ? report.forecasts.plannedIntervals(intersecting: report.selectedYear)
            .filter { focusedRegion == nil || $0.region == focusedRegion }
            .map(\.end).max()
            : nil
        let showsHome = report.showsEstimatedTimeAndPlanning
            && report.forecasts.planning.homeRegion != nil
            && (focusedRegion == nil || report.forecasts.planning.homeRegion == focusedRegion)
        let finalDay = showsHome ? CalendarDay.lastDay(ofYear: report.selectedYear) : lastPlannedDay
        if finalDay == nil,
           report.selectedYear > report.calendar.component(.year, from: report.referenceDate)
        {
            // The year selector retains this selection after plans are hidden or deleted.
            return months
        }
        let lastShownMonth = finalDay.map {
            CalendarDay(year: $0.year, month: $0.month, day: 1).startOfDay(in: report.calendar)
        }.map { max(currentMonthStart, $0) } ?? currentMonthStart
        return months.filter { $0.startOfMonth <= lastShownMonth }
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

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
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

    private var monthName: String {
        month.startOfMonth.formatted(.dateTime.month(.wide))
    }

    private var accessibilityValue: String {
        WhereFormat.calendarMonthAccessibility(
            regionTotals: month.regionTotals,
            regionCombinationTotals: month.regionCombinationTotals,
            needsAttentionDays: month.days.count(where: \.needsAttention),
            evidenceDays: month.days.count(where: \.hasEvidence),
            plannedRegionTotals: [],
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: calendar.month.sectionSpacing) {
            Text(monthName)
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: calendar.month.gridSpacing),
                    count: month.weekdayCount,
                ),
                spacing: calendar.month.gridSpacing,
            ) {
                ForEach(month.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: calendar.month.weekdayFontSize))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0 ..< month.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(minHeight: calendar.day.minHeight)
                }

                ForEach(Array(month.days.enumerated()), id: \.element.id) { index, day in
                    DayCell(day: day, band: bandGeometry(at: index), dateCalendar: dateCalendar)
                }
            }

            if !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
            ForEach(
                planningSummary.filter { focusedRegion == nil || $0.region == focusedRegion },
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
            // Past months use the plain card; the current one gets the accent
            // card (bluer wash, text, and heavier border).
            cardShape
                .fill(card.fill)
                .overlay {
                    cardShape.strokeBorder(card.border, lineWidth: card.borderWidth)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(monthName)
        .accessibilityValue(accessibilityValue)
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

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.day.numberDotSpacing) {
            Text("\(day.dayOfMonth)")
                .font(.system(size: calendar.day.numberFontSize))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(dayNumberColor)
                .frame(width: calendar.day.numberSize, height: calendar.day.numberSize)
                .background {
                    if day.isToday {
                        Circle()
                            .fill(calendar.day.todayMarker)
                    } else if day.needsAttention {
                        Circle()
                            .fill(calendar.day.unresolvedMarker)
                    }
                }
                // A day carrying an attachment gets a small paperclip badge in
                // the top-trailing corner, on a filled disc so it stays legible
                // over the accent "today" fill and the region dots below.
                .overlay(alignment: .topTrailing) {
                    if day.hasEvidence {
                        Image(systemSymbol: .paperclip)
                            .font(.system(size: calendar.day.evidenceBadge.iconSize, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(calendar.day.evidenceBadge.padding)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(
                                x: calendar.day.evidenceBadge.offset.width,
                                y: calendar.day.evidenceBadge.offset.height,
                            )
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
        .accessibilityValue(band.regions.map { region in
            guard let membership = band.memberships[region] else { return region.localizedName }
            return String(localized: .planningCalendarMonthSummary(
                region.localizedName,
                WhereFormat.planningMembership(membership),
            ))
        }.joined(separator: "; "))
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
            .primary
        }
    }
}

#if DEBUG
    extension CalendarContentView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
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
