import Foundation

public enum PresenceCalendarError: Error, Equatable {
    case missingWeekdayRange
    case missingYearStart(year: Int)
    case missingMonthRange(year: Int)
    case missingMonthStart(year: Int, month: Int)
    case missingDayRange(year: Int, month: Int)
    case missingDayDate(year: Int, month: Int, day: Int)
}

/// One cell in a month grid: a real calendar day plus the regions present that
/// day (sorted by `Region.allCases` so dot order is stable).
public struct CalendarDayCell: Hashable, Sendable, Identifiable {
    public let date: Date
    public let dayOfMonth: Int
    public let regions: [Region]
    public let isToday: Bool
    /// Whether this day still needs a location logged (matches the Primary
    /// tab's missing-day banner/backfill rules).
    public let needsAttention: Bool

    public var id: Date {
        date
    }

    public init(
        date: Date,
        dayOfMonth: Int,
        regions: [Region],
        isToday: Bool,
        needsAttention: Bool,
    ) {
        self.date = date
        self.dayOfMonth = dayOfMonth
        self.regions = regions
        self.isToday = isToday
        self.needsAttention = needsAttention
    }
}

/// A single month laid out for a grid: leading blank cells (so day 1 lands on
/// the right weekday column) followed by every day in the month.
public struct CalendarMonth: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let startOfMonth: Date
    public let leadingBlankCount: Int
    public let weekdayCount: Int
    public let weekdaySymbols: [String]
    public let isCurrentMonth: Bool
    public let days: [CalendarDayCell]

    public var id: String {
        "\(year)-\(month)"
    }

    public init(
        year: Int,
        month: Int,
        startOfMonth: Date,
        leadingBlankCount: Int,
        weekdayCount: Int,
        weekdaySymbols: [String],
        isCurrentMonth: Bool,
        days: [CalendarDayCell],
    ) {
        self.year = year
        self.month = month
        self.startOfMonth = startOfMonth
        self.leadingBlankCount = leadingBlankCount
        self.weekdayCount = weekdayCount
        self.weekdaySymbols = weekdaySymbols
        self.isCurrentMonth = isCurrentMonth
        self.days = days
    }
}

/// Builds month grids from a `YearReport`. Pure calendar layout derived from
/// `DayPresence`, parallel to `PresenceTimeline` in WhereUI.
public enum PresenceCalendar {
    /// Build every month in `report.year`. `missingDates` should be start-of-day
    /// keys in the same `calendar` used here and in `DayAggregator`.
    public static func months(
        from report: YearReport,
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
    ) throws -> [CalendarMonth] {
        var regionsByDay: [Date: Set<Region>] = [:]
        for day in report.days {
            let key = calendar.startOfDay(for: day.date)
            regionsByDay[key] = day.regions
        }

        guard
            let yearStart = calendar.date(from: DateComponents(
                year: report.year,
                month: 1,
                day: 1,
            ))
        else {
            throw PresenceCalendarError.missingYearStart(year: report.year)
        }
        guard let monthRange = calendar.range(of: .month, in: .year, for: yearStart) else {
            throw PresenceCalendarError.missingMonthRange(year: report.year)
        }

        let normalizedMissing = Set(missingDates.map { calendar.startOfDay(for: $0) })
        let referenceStartOfDay = calendar.startOfDay(for: referenceDate)

        return try monthRange.map { monthNumber in
            try Self.month(
                year: report.year,
                month: monthNumber,
                regionsByDay: regionsByDay,
                calendar: calendar,
                referenceDate: referenceStartOfDay,
                missingDates: normalizedMissing,
            )
        }
    }

    public static func month(
        year: Int,
        month: Int,
        regionsByDay: [Date: Set<Region>],
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
    ) throws -> CalendarMonth {
        guard
            let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else {
            throw PresenceCalendarError.missingMonthStart(year: year, month: month)
        }
        let startOfMonth = calendar.startOfDay(for: firstOfMonth)
        guard let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            throw PresenceCalendarError.missingDayRange(year: year, month: month)
        }
        let numberOfDays = dayRange.count
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let weekdayCount = try Self.weekdayCount(in: calendar)
        let leadingBlankCount = (weekday - calendar.firstWeekday + weekdayCount) % weekdayCount
        let weekdaySymbols = Self.orderedWeekdaySymbols(in: calendar)
        let isCurrentMonth = calendar.isDate(
            startOfMonth,
            equalTo: referenceDate,
            toGranularity: .month,
        )

        var days: [CalendarDayCell] = []
        days.reserveCapacity(numberOfDays)
        for dayOfMonth in 1 ... numberOfDays {
            guard
                let date = calendar.date(
                    byAdding: .day,
                    value: dayOfMonth - 1,
                    to: startOfMonth,
                )
            else {
                throw PresenceCalendarError.missingDayDate(
                    year: year,
                    month: month,
                    day: dayOfMonth,
                )
            }
            let regions: [Region] = if let dayRegions = regionsByDay[date] {
                Region.allCases.filter { dayRegions.contains($0) }
            } else {
                []
            }
            days.append(CalendarDayCell(
                date: date,
                dayOfMonth: dayOfMonth,
                regions: regions,
                isToday: calendar.isDate(date, inSameDayAs: referenceDate),
                needsAttention: missingDates.contains(date),
            ))
        }

        return CalendarMonth(
            year: year,
            month: month,
            startOfMonth: startOfMonth,
            leadingBlankCount: leadingBlankCount,
            weekdayCount: weekdayCount,
            weekdaySymbols: weekdaySymbols,
            isCurrentMonth: isCurrentMonth,
            days: days,
        )
    }

    private static func weekdayCount(in calendar: Calendar) throws -> Int {
        guard let count = calendar.maximumRange(of: .weekday)?.count else {
            throw PresenceCalendarError.missingWeekdayRange
        }
        return count
    }

    private static func orderedWeekdaySymbols(in calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}

extension YearReport {
    /// Month grids for the calendar sheet. Pass the same `calendar` and
    /// start-of-day `missingDates` keys used by `MissingDays` and
    /// `DayAggregator`.
    public func calendarMonths(
        calendar: Calendar,
        referenceDate: Date,
        missingDates: Set<Date> = [],
    ) throws -> [CalendarMonth] {
        try PresenceCalendar.months(
            from: self,
            calendar: calendar,
            referenceDate: referenceDate,
            missingDates: missingDates,
        )
    }
}
