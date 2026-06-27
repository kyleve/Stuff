import SwiftUI
import WhereCore

/// A scrollable year calendar: one month grid per month, with colored dots for
/// each region present on a day. Tapping a day pushes the full-year timeline
/// auto-scrolled to that month. Presented as a sheet from the Primary tab.
struct CalendarView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var timelineTarget: TimelineMonthTarget?

    private static let logger = WhereLog.channel(.session)

    private struct TimelineMonthTarget: Hashable, Identifiable {
        let startOfMonth: Date
        var id: Date {
            startOfMonth
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let report = session.report {
                    calendarContent(months: report.calendarMonths(
                        calendar: session.dayCalendar,
                        referenceDate: session.referenceDate,
                        missingDates: session.missingDayKeys,
                    ))
                } else if session.loadState == .loading {
                    ProgressView(Strings.primaryLoading)
                } else if case let .failed(message) = session.loadState {
                    ContentUnavailableView {
                        Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(message)
                    }
                } else {
                    ContentUnavailableView {
                        Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(Strings.calendarUnavailableDescription)
                    }
                    .onAppear {
                        Self.logger.warning(
                            "Calendar opened without a year report (loadState: \(session.loadState))",
                        )
                    }
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

    private func calendarContent(months: [CalendarMonth]) -> some View {
        ScrollViewReader { proxy in
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
        guard let targetID = months.first(where: \.isCurrentMonth)?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(targetID, anchor: .top)
        }
    }
}

/// One month section: weekday header row plus a day grid.
private struct MonthGridView: View {
    let month: CalendarMonth
    let onSelectDay: (CalendarDayCell) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.medium) {
            Text(month.startOfMonth.formatted(.dateTime.month(.wide)))
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: UIConstants.Spacings.small),
                    count: month.weekdayCount,
                ),
                spacing: UIConstants.Spacings.small,
            ) {
                ForEach(month.weekdaySymbols, id: \.self) { symbol in
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
            if month.isCurrentMonth {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.compactCard)
                    .fill(Color.accentColor.opacity(0.08))
            }
        }
    }
}

/// One day in the month grid: the day number and region-colored dots below.
private struct DayCell: View {
    let day: CalendarDayCell

    var body: some View {
        VStack(spacing: UIConstants.Spacings.xxSmall) {
            Text("\(day.dayOfMonth)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(dayNumberColor)
                .frame(width: 26, height: 26)
                .background {
                    if day.isToday {
                        Circle()
                            .fill(Color.accentColor)
                    } else if day.needsAttention {
                        Circle()
                            .fill(Color.red.opacity(0.15))
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
        .accessibilityLabel(
            Strings.calendarDayAccessibility(
                date: day.date,
                regions: day.regions,
                needsAttention: day.needsAttention,
            ),
        )
    }

    private var dayNumberColor: Color {
        if day.isToday {
            .white
        } else if day.needsAttention {
            .red
        } else {
            .primary
        }
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

    #Preview("Missing days") {
        CalendarView()
            .environment(PreviewSupport.missingDaysSession())
    }
#endif
