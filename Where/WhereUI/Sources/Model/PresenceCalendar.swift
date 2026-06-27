import Foundation
import WhereCore

/// One cell in a month grid: a real calendar day plus the regions present that
/// day (sorted by `Region.allCases` so dot order is stable).
public struct CalendarDayCell: Hashable, Sendable, Identifiable {
    public let date: Date
    public let dayOfMonth: Int
    public let regions: [Region]

    public var id: Date {
        date
    }

    public init(date: Date, dayOfMonth: Int, regions: [Region]) {
        self.date = date
        self.dayOfMonth = dayOfMonth
        self.regions = regions
    }
}

/// A single month laid out for a grid: leading blank cells (so day 1 lands on
/// the right weekday column) followed by every day in the month.
public struct CalendarMonth: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let startOfMonth: Date
    public let leadingBlankCount: Int
    public let days: [CalendarDayCell]

    public var id: String {
        "\(year)-\(month)"
    }

    public init(
        year: Int,
        month: Int,
        startOfMonth: Date,
        leadingBlankCount: Int,
        days: [CalendarDayCell],
    ) {
        self.year = year
        self.month = month
        self.startOfMonth = startOfMonth
        self.leadingBlankCount = leadingBlankCount
        self.days = days
    }
}

/// Builds month grids from a `YearReport`. Presentation logic derived from
/// `DayPresence`, so it lives in `WhereUI` alongside the views that render it.
public enum PresenceCalendar {
    /// Build all 12 months for a year's report. `regionsByDay` is keyed by
    /// `calendar.startOfDay(for:)`.
    public static func months(
        from report: YearReport,
        calendar: Calendar = .current,
    ) -> [CalendarMonth] {
        var regionsByDay: [Date: Set<Region>] = [:]
        for day in report.days {
            let key = calendar.startOfDay(for: day.date)
            regionsByDay[key] = day.regions
        }
        return (1 ... 12).map { monthNumber in
            Self.month(
                year: report.year,
                month: monthNumber,
                regionsByDay: regionsByDay,
                calendar: calendar,
            )
        }
    }

    public static func month(
        year: Int,
        month: Int,
        regionsByDay: [Date: Set<Region>],
        calendar: Calendar = .current,
    ) -> CalendarMonth {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let startOfMonth = calendar.startOfDay(for: firstOfMonth)
        let numberOfDays = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlankCount = (weekday - calendar.firstWeekday + 7) % 7

        let days = (1 ... numberOfDays).map { dayOfMonth in
            let date = calendar.date(
                byAdding: .day,
                value: dayOfMonth - 1,
                to: startOfMonth,
            )!
            let regions = Region.allCases.filter { regionsByDay[date]?.contains($0) == true }
            return CalendarDayCell(date: date, dayOfMonth: dayOfMonth, regions: regions)
        }

        return CalendarMonth(
            year: year,
            month: month,
            startOfMonth: startOfMonth,
            leadingBlankCount: leadingBlankCount,
            days: days,
        )
    }
}
