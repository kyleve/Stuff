import SwiftUI
import WhereCore

/// A month has at most six weeks. Eager rows keep its intrinsic height exact
/// while a zoom destination is offscreen or covered by the transition overlay.
struct CalendarDayGrid: View {
    let month: CalendarMonth
    let weekdaySymbols: [String]
    let dateCalendar: Calendar
    let compact: Bool
    let isAvailable: Bool
    let spacing: CGFloat
    let weekdayFontSize: CGFloat
    let dayHeight: CGFloat
    let bandGeometry: (Int) -> DayBandGeometry

    var body: some View {
        let weekCount = compact ? 6 :
            (month.leadingBlankCount + month.days.count + month.weekdayCount - 1) / month
            .weekdayCount
        Grid(
            horizontalSpacing: spacing,
            verticalSpacing: spacing,
        ) {
            CalendarWeekdayRow(symbols: weekdaySymbols, fontSize: weekdayFontSize)
            ForEach(0 ..< weekCount, id: \.self) { week in
                CalendarWeekRow(
                    month: month,
                    week: week,
                    compact: compact,
                    isAvailable: isAvailable,
                    dateCalendar: dateCalendar,
                    minHeight: dayHeight,
                    bandGeometry: bandGeometry,
                )
            }
        }
    }
}

private struct CalendarWeekdayRow: View {
    let symbols: [String]
    let fontSize: CGFloat

    var body: some View {
        GridRow {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                CalendarWeekdayHeading(symbol: symbol, fontSize: fontSize)
            }
        }
    }
}

private struct CalendarWeekRow: View {
    let month: CalendarMonth
    let week: Int
    let compact: Bool
    let isAvailable: Bool
    let dateCalendar: Calendar
    let minHeight: CGFloat
    let bandGeometry: (Int) -> DayBandGeometry

    var body: some View {
        GridRow {
            ForEach(0 ..< month.weekdayCount, id: \.self) { weekday in
                let index = week * month.weekdayCount + weekday - month.leadingBlankCount
                if month.days.indices.contains(index) {
                    DayCell(
                        day: month.days[index],
                        band: bandGeometry(index),
                        dateCalendar: dateCalendar,
                        compact: compact,
                        isAvailable: isAvailable,
                    )
                } else {
                    Color.clear.frame(height: minHeight)
                }
            }
        }
    }
}

private struct CalendarWeekdayHeading: View {
    let symbol: String
    let fontSize: CGFloat

    var body: some View {
        Text(symbol)
            .font(.system(size: fontSize))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview("Month grid") {
        CalendarMonthSnapshot(report: PreviewSupport.loadedYearReportModel(), monthNumber: 5)
            .whereBroadwayRoot()
    }
#endif
