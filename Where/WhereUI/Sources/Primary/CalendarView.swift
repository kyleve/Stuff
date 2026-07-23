import PeriscopeCore
import RegionKit
import SwiftUI
import WhereCore

/// A sheet wrapper around ``CalendarContentView`` for the region-focused
/// calendar presented from the Locations tab: it owns the `NavigationStack`,
/// the region/year title, and the Done button. The unfocused, full-year
/// calendar is hosted inline by the Your Year tab via ``CalendarContentView``.
struct CalendarView: View {
    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CalendarContentView(focusedRegion: focusedRegion, report: report)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.commonDone) { dismiss() }
                    }
                }
        }
    }

    private var navigationTitle: String {
        if let focusedRegion {
            Strings.calendarRegionTitle(region: focusedRegion, year: report.selectedYear)
        } else {
            Strings.calendarTitle(year: report.selectedYear)
        }
    }
}

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day, and a per-month footer tallying the days spent
/// in each region. Chrome-free (no `NavigationStack` / Done) so it can be hosted
/// inline in the Your Year tab or inside the ``CalendarView`` sheet wrapper.
struct CalendarContentView: View {
    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel

    @Environment(\.stylesheet) private var stylesheet

    @State private var monthsLoad: Result<[CalendarMonth], Error>?
    /// The year we've already positioned to the current month. Doubles as the
    /// reveal gate: the grid stays hidden until it's scrolled into place (so the
    /// jump isn't visible), then shows. Guarded per year so returning to the tab
    /// keeps the user's scroll instead of re-hiding/re-jumping; a year switch
    /// rebuilds the grid and positions afresh.
    @State private var scrolledForYear: Int?

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
                            AppIconLoadingView(caption: Strings.primaryLoading)
                    }
                }
                .task(id: calendarLoadID(report: yearReport)) {
                    let result = loadCalendarMonths(from: yearReport)
                    guard !Task.isCancelled else { return }
                    monthsLoad = result
                }
            } else if report.loadState == .loading {
                AppIconLoadingView(caption: Strings.primaryLoading)
            } else if case let .failed(error) = report.loadState {
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error.message)
                }
            } else {
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(Strings.calendarUnavailableDescription)
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
            Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
        } description: {
            Text(Strings.calendarUnavailableDescription)
        }
        .onAppear {
            Self.logger { .layoutFailed(description: String(describing: error)) }
        }
    }

    private func calendarContent(months: [CalendarMonth]) -> some View {
        // Start of the month containing "today", so months after it read as
        // future. `nil` (no interval) falls back to never dimming.
        let currentMonthStart = report.calendar
            .dateInterval(of: .month, for: report.referenceDate)?
            .start
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: stylesheet.calendar.monthSpacing) {
                    ForEach(months) { month in
                        MonthGridView(
                            month: month,
                            focusedRegion: focusedRegion,
                            isFuture: currentMonthStart.map { month.startOfMonth > $0 } ?? false,
                        )
                        .id(month.id)
                    }
                }
                .padding()
            }
            // Hidden until positioned so the jump to the current month isn't
            // visible; revealed once scrolled into place (see below).
            .opacity(scrolledForYear == report.selectedYear ? 1 : 0)
            .onAppear { positionToCurrentMonthIfNeeded(proxy, months: months) }
        }
    }

    /// Scrolls to the current month once per year while the grid is still hidden
    /// (a `scrollTo` to a lazy month has to run after layout, so it's deferred a
    /// tick), then reveals it — so the user sees the calendar appear already at
    /// the current month rather than watching it jump there. Reappearing (a tab
    /// return) skips this and keeps the user's scroll; a year switch rebuilds
    /// the grid and positions afresh. A past year has no current month, so it
    /// simply reveals from the top.
    private func positionToCurrentMonthIfNeeded(_ proxy: ScrollViewProxy, months: [CalendarMonth]) {
        guard scrolledForYear != report.selectedYear else { return }
        let targetID = months.first(where: \.isCurrentMonth)?.id
        DispatchQueue.main.async {
            if let targetID {
                proxy.scrollTo(targetID, anchor: .top)
            }
            scrolledForYear = report.selectedYear
        }
    }
}

/// One month section: weekday header row, a day grid, and a footer tallying the
/// days spent in each region that month.
private struct MonthGridView: View {
    let month: CalendarMonth
    /// The region the calendar is focused on, if any — emphasized in the footer.
    var focusedRegion: Region?
    /// Whether this month is entirely in the future (dimmed when so).
    var isFuture: Bool

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: calendar.month.sectionSpacing) {
            Text(month.startOfMonth.formatted(.dateTime.month(.wide)))
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0 ..< month.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(minHeight: calendar.dayMinHeight)
                }

                ForEach(Array(month.days.enumerated()), id: \.element.id) { index, day in
                    DayCell(day: day, band: bandGeometry(at: index))
                }
            }

            if !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
        }
        .padding(calendar.month.padding)
        .background {
            RoundedRectangle(cornerRadius: calendar.month.cornerRadius)
                .fill(month.isCurrentMonth ? calendar.month.currentMonthHighlight : calendar.month
                    .background)
        }
        // Dim months that haven't happened yet.
        .opacity(isFuture ? calendar.month.futureOpacity : 1)
    }

    /// The stay-pill geometry for the day at `index`: a run is contiguous days
    /// with the identical region set, so its true ends round fully while a run
    /// spilling across a week boundary rounds subtly (and same-row neighbours
    /// extend half the grid gap so the pill reads as one connected shape).
    private func bandGeometry(at index: Int) -> DayBandGeometry {
        let days = month.days
        let day = days[index]
        guard !day.regions.isEmpty else { return .none }

        let regionSet = Set(day.regions)
        let column = (month.leadingBlankCount + index) % month.weekdayCount
        let isRowStart = column == 0
        let isRowEnd = column == month.weekdayCount - 1
        let joinsLeft = index > 0 && Set(days[index - 1].regions) == regionSet
        let joinsRight = index < days.count - 1 && Set(days[index + 1].regions) == regionSet

        let band = calendar.regionBand
        let halfGap = calendar.month.gridSpacing / 2
        return DayBandGeometry(
            regions: day.regions,
            leadingRadius: joinsLeft ? (isRowStart ? band.continuationRadius : 0) : band
                .cornerRadius,
            trailingRadius: joinsRight ? (isRowEnd ? band.continuationRadius : 0) : band
                .cornerRadius,
            extendLeading: joinsLeft && !isRowStart ? halfGap : 0,
            extendTrailing: joinsRight && !isRowEnd ? halfGap : 0,
        )
    }
}

/// How to draw a day's slice of the region "stay" pill: which corners round
/// (the run's ends) and how far to bleed into the grid gaps so a run reads as
/// one connected shape. Empty `regions` means no pill.
private struct DayBandGeometry {
    var regions: [Region]
    var leadingRadius: CGFloat
    var trailingRadius: CGFloat
    var extendLeading: CGFloat
    var extendTrailing: CGFloat

    static let none = DayBandGeometry(
        regions: [],
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
        return HStack(spacing: calendar.month.footerRowSpacing) {
            Circle()
                .fill(regionStyles.style(for: tally.region).tint)
                .frame(
                    width: calendar.dotSize,
                    height: calendar.dotSize,
                )
            Text(tally.region.localizedName)
                .font(.subheadline)
                .fontWeight(isFocused ? .semibold : .regular)
            Spacer(minLength: 0)
            Text(Strings.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Strings.regionDaysAccessibility(
                region: tally.region.localizedName,
                days: tally.days,
            ),
        )
    }
}

/// One day in the month grid: the day number, region-presence dots beneath it,
/// and a subtle region-tinted "stay" pill behind it that connects to adjacent
/// days in the same run so a stretch in one place reads as a single shape.
private struct DayCell: View {
    let day: CalendarDayCell
    /// The stay-pill slice for this day (computed by the enclosing month).
    let band: DayBandGeometry

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.dayNumberDotSpacing) {
            Text("\(day.dayOfMonth)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(dayNumberColor)
                .frame(width: calendar.dayNumberSize, height: calendar.dayNumberSize)
                .background {
                    if day.isToday {
                        Circle()
                            .fill(calendar.todayMarker)
                    } else if day.needsAttention {
                        Circle()
                            .fill(calendar.unresolvedDayMarker)
                    }
                }
                // A day carrying an attachment gets a small paperclip badge in
                // the top-trailing corner, on a filled disc so it stays legible
                // over the accent "today" fill and the region dots below.
                .overlay(alignment: .topTrailing) {
                    if day.hasEvidence {
                        Image(systemName: "paperclip")
                            .font(.system(size: calendar.evidenceBadge.iconSize, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(calendar.evidenceBadge.padding)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(
                                x: calendar.evidenceBadge.offset.width,
                                y: calendar.evidenceBadge.offset.height,
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
        .frame(minHeight: calendar.dayMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Strings.calendarDayAccessibility(
                date: day.date,
                regions: day.regions,
                needsAttention: day.needsAttention,
                hasEvidence: day.hasEvidence,
            ),
        )
    }

    /// Region-presence dots beneath the day number (one per region the day
    /// counts for), each with a subtle background-colored rim. On a multi-region
    /// day the dots overlap into a cluster, the rims keeping them distinct.
    /// Empty days keep the row height so the grid baseline is even.
    private var dots: some View {
        let isCluster = day.regions.count > 1
        return HStack(spacing: isCluster ? -calendar.dayDotOverlap : calendar.dayContentSpacing) {
            ForEach(day.regions, id: \.self) { region in
                Circle()
                    .fill(regionStyles.style(for: region).tint)
                    .frame(width: calendar.dayDotSize, height: calendar.dayDotSize)
                    .overlay {
                        Circle().stroke(
                            Color(.systemBackground),
                            lineWidth: calendar.dayDotStrokeWidth,
                        )
                    }
            }
        }
        .frame(height: calendar.dayDotSize)
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
                UnevenRoundedRectangle(
                    topLeadingRadius: band.leadingRadius,
                    bottomLeadingRadius: band.leadingRadius,
                    bottomTrailingRadius: band.trailingRadius,
                    topTrailingRadius: band.trailingRadius,
                )
                .fill(pillFill)
                .opacity(calendar.regionBand.opacity)
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
            calendar.todayNumberColor
        } else if day.needsAttention {
            calendar.unresolvedNumberColor
        } else {
            .primary
        }
    }
}

#if DEBUG
    #Preview("Sheet") {
        CalendarView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Focused") {
        CalendarView(focusedRegion: .california, report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Content loaded") {
        NavigationStack {
            CalendarContentView(report: PreviewSupport.loadedYearReportModel())
        }
    }

    #Preview("Content empty") {
        NavigationStack {
            CalendarContentView(report: PreviewSupport.emptyYearReportModel())
        }
    }

    #Preview("Content missing days") {
        NavigationStack {
            CalendarContentView(report: PreviewSupport.missingDaysYearReportModel())
        }
    }
#endif
