import RegionKit
import SwiftUI
import WhereCore

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day, and a per-month footer tallying the days spent
/// in each region. Tapping a day pushes the full-year timeline auto-scrolled to
/// that month. Presented as a sheet from the Primary tab — either unfiltered
/// (toolbar) or focused on a single region (tapping a region card).
struct CalendarView: View {
    /// When set, the day grid only shows dots for this region (so it reads as
    /// "just the days I spent here"); the per-month footer still lists every
    /// region. `nil` shows every region's dots.
    var focusedRegion: Region?

    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet

    @State private var timelineTarget: TimelineMonthTarget?
    @State private var monthsLoad: Result<[CalendarMonth], Error>?

    private static let logger = WhereLog.channel(.session)

    /// Inputs that invalidate a cached month grid.
    private struct CalendarLoadID: Equatable {
        let report: YearReport
        let missingDayKeys: Set<Date>
        let evidenceDayKeys: Set<Date>
        let referenceDay: Date
        let focusedRegion: Region?
    }

    private struct TimelineMonthTarget: Hashable, Identifiable {
        let startOfMonth: Date
        var id: Date {
            startOfMonth
        }
    }

    var body: some View {
        NavigationStack {
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
                        Label(.commonLoadErrorTitle, systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(error.message)
                    }
                } else {
                    ContentUnavailableView {
                        Label(.commonLoadErrorTitle, systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(.calendarUnavailableDescription)
                    }
                    .onAppear {
                        Self.logger.warning(
                            "Calendar opened without a year report (loadState: \(report.loadState))",
                        )
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.commonDone) { dismiss() }
                }
            }
            .navigationDestination(item: $timelineTarget) { target in
                PresenceTimelineList(report: report, scrollToMonth: target.startOfMonth)
                    .navigationTitle(String(localized: .timelineTitle(WhereFormat
                            .year(report.selectedYear))))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var navigationTitle: String {
        if let focusedRegion {
            String(localized: .calendarRegionTitle(
                focusedRegion.localizedName,
                WhereFormat.year(report.selectedYear),
            ))
        } else {
            String(localized: .calendarTitle(WhereFormat.year(report.selectedYear)))
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
            Label(.commonLoadErrorTitle, systemImage: "exclamationmark.icloud")
        } description: {
            Text(.calendarUnavailableDescription)
        }
        .onAppear {
            Self.logger.warning("Calendar layout failed: \(error)")
        }
    }

    private func calendarContent(months: [CalendarMonth]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: stylesheet.calendar.monthSpacing) {
                    ForEach(months) { month in
                        MonthGridView(month: month, focusedRegion: focusedRegion) { _ in
                            timelineTarget = TimelineMonthTarget(startOfMonth: month.startOfMonth)
                        }
                        .id(month.id)
                    }
                }
                .padding()
            }
            .onAppear {
                scrollToCurrentMonth(proxy, months: months)
            }
        }
    }

    /// When viewing the current year, scrolls the grid to today's month.
    private func scrollToCurrentMonth(_ proxy: ScrollViewProxy, months: [CalendarMonth]) {
        guard let targetID = months.first(where: \.isCurrentMonth)?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(targetID, anchor: .top)
        }
    }
}

/// One month section: weekday header row, a day grid, and a footer tallying the
/// days spent in each region that month.
private struct MonthGridView: View {
    let month: CalendarMonth
    /// The region the calendar is focused on, if any — emphasized in the footer.
    var focusedRegion: Region?
    let onSelectDay: (CalendarDayCell) -> Void

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

                ForEach(month.days) { day in
                    Button {
                        onSelectDay(day)
                    } label: {
                        DayCell(day: day)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !month.regionTotals.isEmpty {
                MonthFooter(totals: month.regionTotals, focusedRegion: focusedRegion)
            }
        }
        .padding(calendar.month.padding)
        .background {
            if month.isCurrentMonth {
                RoundedRectangle(cornerRadius: calendar.month.cornerRadius)
                    .fill(calendar.month.currentMonthHighlight)
            }
        }
    }
}

/// The per-month footer: one row per region present that month, showing its dot
/// color and how many days were spent there. The focused region (if any) is
/// emphasized so it stands out from the surrounding context rows.
private struct MonthFooter: View {
    let totals: [RegionDayTally]
    var focusedRegion: Region?

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.month.footerSpacing) {
            Divider()
            ForEach(totals) { tally in
                row(for: tally)
            }
        }
    }

    private func row(for tally: RegionDayTally) -> some View {
        let isFocused = tally.region == focusedRegion
        return HStack(spacing: calendar.month.footerRowSpacing) {
            Circle()
                .fill(tally.region.style.tint)
                .frame(
                    width: calendar.dotSize,
                    height: calendar.dotSize,
                )
            Text(tally.region.localizedName)
                .font(.subheadline)
                .fontWeight(isFocused ? .semibold : .regular)
            Spacer(minLength: 0)
            Text(WhereFormat.dayCount(tally.days))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(focusedRegion == nil || isFocused ? 1 : calendar.month.unfocusedRowOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.regionDaysAccessibility(
                region: tally.region.localizedName,
                days: tally.days,
            ),
        )
    }
}

/// One day in the month grid: the day number and region-colored dots below.
private struct DayCell: View {
    let day: CalendarDayCell

    @Environment(\.stylesheet) private var stylesheet

    private var calendar: WhereStylesheet.CalendarStyle {
        stylesheet.calendar
    }

    var body: some View {
        VStack(spacing: calendar.dayContentSpacing) {
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

            HStack(spacing: calendar.dayContentSpacing) {
                ForEach(day.regions, id: \.self) { region in
                    Circle()
                        .fill(region.style.tint)
                        .frame(
                            width: calendar.dotSize,
                            height: calendar.dotSize,
                        )
                }
            }
            .frame(height: calendar.dotSize)
        }
        .frame(maxWidth: .infinity, minHeight: calendar.dayMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.calendarDayAccessibility(
                date: day.date,
                regions: day.regions,
                needsAttention: day.needsAttention,
                hasEvidence: day.hasEvidence,
            ),
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
    #Preview("Loaded") {
        CalendarView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Focused") {
        CalendarView(focusedRegion: .california, report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        CalendarView(report: PreviewSupport.emptyYearReportModel())
    }

    #Preview("Missing days") {
        CalendarView(report: PreviewSupport.missingDaysYearReportModel())
    }
#endif
