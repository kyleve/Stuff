import Foundation

/// Resolves a logical day from a device's positively established calendar-context intervals.
/// Unknown intervals prevent a whole-day save. The supplied search period must bound every
/// occurrence of the requested date; completeness is an explicit caller obligation.
public enum RecordingDayCoverage {
    public struct Context: Hashable, Codable, Sendable {
        public let period: RecordingPeriod
        public let calendarContext: RecordingCalendarContext

        public init(period: RecordingPeriod, calendarContext: RecordingCalendarContext) {
            self.period = period
            self.calendarContext = calendarContext
        }
    }

    public enum Resolution: Hashable, Sendable {
        case resolved([RecordingPeriod])
        case needsContext([RecordingPeriod])
    }

    public enum ValidationError: Error {
        case invalidDay
        case conflictingContext
        case unavailableCalendarBoundary
    }

    /// Every supported fixed offset lies within eighteen hours of UTC. This search includes
    /// every occurrence of a logical date, including a repeated date after a date-line crossing.
    public static func searchPeriod(for day: CalendarDay) throws -> RecordingPeriod {
        guard (1 ... 9999).contains(day.year), CalendarDay(iso: day.iso8601) == day else {
            throw ValidationError.invalidDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let instant = calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
        )), let bounds = calendar.dateInterval(of: .day, for: instant) else {
            throw ValidationError.unavailableCalendarBoundary
        }
        let maximumOffset: TimeInterval = 18 * 60 * 60
        return try RecordingPeriod(
            start: bounds.start.addingTimeInterval(-maximumOffset),
            end: bounds.end.addingTimeInterval(maximumOffset),
        )
    }

    public static func resolve(
        day: CalendarDay,
        within searchPeriod: RecordingPeriod,
        contexts: [Context],
    ) throws -> Resolution {
        guard CalendarDay(iso: day.iso8601) == day else { throw ValidationError.invalidDay }
        try searchPeriod.validate()
        for context in contexts {
            try context.period.validate()
            try context.calendarContext.validate()
        }
        let relevant = contexts.filter { $0.period.overlaps(searchPeriod) }
        for (index, context) in relevant.enumerated() {
            for other in relevant.dropFirst(index + 1)
                where context.period.overlaps(other.period) && context.calendarContext != other
                .calendarContext
            {
                throw ValidationError.conflictingContext
            }
        }
        let covered = RecordingPeriod.union(relevant.compactMap {
            $0.period.intersection(searchPeriod)
        })
        var missing: [RecordingPeriod] = []
        var cursor = searchPeriod.start
        for period in covered {
            if cursor < period.start {
                try missing.append(RecordingPeriod(start: cursor, end: period.start))
            }
            cursor = period.end
        }
        if cursor < searchPeriod.end {
            try missing.append(RecordingPeriod(start: cursor, end: searchPeriod.end))
        }
        guard missing.isEmpty else { return .needsContext(missing) }

        var periods: [RecordingPeriod] = []
        for context in relevant {
            let calendar = try context.calendarContext.calendar()
            guard let instant = calendar.date(from: DateComponents(
                year: day.year,
                month: day.month,
                day: day.day,
            )) else { throw ValidationError.unavailableCalendarBoundary }
            // A skipped local date (for example Samoa's 2011-12-30) has no coverage.
            guard CalendarDay(from: instant, in: calendar) == day else { continue }
            guard let bounds = calendar.dateInterval(of: .day, for: instant) else {
                throw ValidationError.unavailableCalendarBoundary
            }
            let dayPeriod = try RecordingPeriod(start: bounds.start, end: bounds.end)
            if let overlap = dayPeriod.intersection(context.period)?.intersection(searchPeriod) {
                periods.append(overlap)
            }
        }
        return .resolved(RecordingPeriod.union(periods))
    }
}
