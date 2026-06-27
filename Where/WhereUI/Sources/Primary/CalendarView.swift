import SwiftUI
import WhereCore

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day. Tapping a day pushes the full-year timeline
/// auto-scrolled to that month. Presented as a sheet from the Primary tab.
struct CalendarView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var timelineTarget: TimelineMonthTarget?

    private struct TimelineMonthTarget: Hashable, Identifiable {
        let startOfMonth: Date
        var id: Date {
            startOfMonth
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.report == nil {
                    ProgressView(Strings.primaryLoading)
                } else {
                    calendarContent
                }
            }
            .navigationTitle(Strings.calendarTitle(year: session.selectedYear))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.commonDone) { dismiss() }
                }
            }
            .navigationDestination(item: $timelineTarget) { target in
                PresenceTimelineList(scrollToMonth: target.startOfMonth)
                    .navigationTitle(Strings.timelineTitle(year: session.selectedYear))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var calendarContent: some View {
        let months = PresenceCalendar.months(from: session.report!)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: UIConstants.Spacings.xxLarge) {
                    ForEach(months) { month in
                        MonthGridView(month: month) { _ in
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
        guard let targetID = currentMonthID(in: months) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(targetID, anchor: .top)
        }
    }

    private func currentMonthID(in months: [CalendarMonth]) -> String? {
        let calendar = Calendar.current
        let now = Date()
        guard calendar.component(.year, from: now) == session.selectedYear else { return nil }
        let month = calendar.component(.month, from: now)
        return months.first { $0.month == month }?.id
    }
}

/// One month section: weekday header row plus a 7-column day grid.
private struct MonthGridView: View {
    let month: CalendarMonth
    let onSelectDay: (CalendarDayCell) -> Void

    private var calendar: Calendar {
        .current
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(month.startOfMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.medium) {
            Text(month.startOfMonth.formatted(.dateTime.month(.wide)))
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: UIConstants.Spacings.small),
                    count: 7,
                ),
                spacing: UIConstants.Spacings.small,
            ) {
                ForEach(orderedWeekdaySymbols(calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0 ..< month.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(minHeight: UIConstants.Size.calendarDayMinHeight)
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
        }
        .padding(UIConstants.Padding.compactCard)
        .background {
            if isCurrentMonth {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.compactCard)
                    .fill(Color.accentColor.opacity(0.08))
            }
        }
    }

    private func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

/// One day in the month grid: the day number and region-colored dots below.
private struct DayCell: View {
    let day: CalendarDayCell

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacings.xxSmall) {
            Text("\(day.dayOfMonth)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background {
                    if isToday {
                        Circle()
                            .fill(Color.accentColor)
                    }
                }

            HStack(spacing: UIConstants.Spacings.xxSmall) {
                ForEach(day.regions, id: \.self) { region in
                    Circle()
                        .fill(region.style.tint)
                        .frame(
                            width: UIConstants.Size.calendarDot,
                            height: UIConstants.Size.calendarDot,
                        )
                }
            }
            .frame(height: UIConstants.Size.calendarDot)
        }
        .frame(maxWidth: .infinity, minHeight: UIConstants.Size.calendarDayMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.calendarDayAccessibility(date: day.date, regions: day.regions))
    }
}

#if DEBUG
    #Preview("Loaded") {
        CalendarView()
            .environment(PreviewSupport.loadedSession())
    }

    #Preview("Empty") {
        CalendarView()
            .environment(PreviewSupport.emptySession())
    }
#endif
