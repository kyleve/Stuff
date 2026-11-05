import Foundation

/// Search years containing actual history or unresolved possible dates. Possible years do not
/// assign a logical date to an observation or make its history eligible for totals.
struct HistoryYearInventory {
    enum ValidationError: Error, Equatable { case unsupportedDate }

    private(set) var years: Set<Int> = []
    private static let supportedYears = 1 ... 9999

    mutating func include(day: CalendarDay) throws {
        guard Self.supportedYears.contains(day.year), CalendarDay(iso: day.iso8601) == day else {
            throw ValidationError.unsupportedDate
        }
        years.insert(day.year)
    }

    mutating func include(timestamp: Date, calendar: Calendar) throws {
        let year = try Self.year(at: timestamp, calendar: calendar)
        guard Self.supportedYears.contains(year) else { throw ValidationError.unsupportedDate }
        years.insert(year)
    }

    mutating func includePossibleYears(at timestamp: Date) throws {
        try includePossibleYears(
            from: Self.year(at: timestamp, calendar: Self.extremeCalendar(sign: -1)),
            through: Self.year(at: timestamp, calendar: Self.extremeCalendar(sign: 1)),
        )
    }

    mutating func includePossibleYears(in period: RecordingPeriod) throws {
        try period.validate()
        let calendar = Self.extremeCalendar(sign: 1)
        var last = try Self.year(at: period.end, calendar: calendar)
        // Exclude an exact year boundary, without subtracting a second from a subsecond period.
        if calendar.dateInterval(of: .year, for: period.end)?.start == period.end {
            last -= 1
        }
        try includePossibleYears(
            from: Self.year(at: period.start, calendar: Self.extremeCalendar(sign: -1)),
            through: last,
        )
    }

    private mutating func includePossibleYears(from first: Int, through last: Int) throws {
        let lower = max(first, Self.supportedYears.lowerBound)
        let upper = min(last, Self.supportedYears.upperBound)
        guard lower <= upper else { throw ValidationError.unsupportedDate }
        years.formUnion(lower ... upper)
    }

    private static func extremeCalendar(sign: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Both offsets are fixed supported constants, independent of the current zone database.
        calendar
            .timeZone = TimeZone(secondsFromGMT: sign * Int(RecordingDayCoverage.maximumOffset))!
        return calendar
    }

    private static func year(at timestamp: Date, calendar: Calendar) throws -> Int {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw ValidationError.unsupportedDate
        }
        let parts = calendar.dateComponents([.era, .year], from: timestamp)
        guard let era = parts.era, let year = parts.year, year > 0, era == 0 || era == 1 else {
            throw ValidationError.unsupportedDate
        }
        // Possible dates can straddle the supported year-one boundary. Clamp that search range
        // after converting the Gregorian era, instead of interpreting 1 BCE as 1 CE.
        return era == 1 ? year : 1 - year
    }
}
