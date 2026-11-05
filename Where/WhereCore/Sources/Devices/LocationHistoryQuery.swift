import Foundation

/// A logical date range is independent of the viewing zone. Store reads cover every supported
/// recording offset; callers filter selected contributions by logical day after assessment.
public enum LocationHistoryQuery: Hashable, Sendable {
    case instants(RecordingPeriod)
    case days(ClosedRange<CalendarDay>)

    public func recordingPeriod() throws -> RecordingPeriod {
        switch self {
            case let .instants(period):
                try period.validate()
                return period
            case let .days(days):
                let first = try RecordingDayCoverage.searchPeriod(for: days.lowerBound)
                let last = try RecordingDayCoverage.searchPeriod(for: days.upperBound)
                return try RecordingPeriod(start: first.start, end: last.end)
        }
    }

    public func viewingPeriod(in calendar: Calendar) throws -> RecordingPeriod {
        switch self {
            case let .instants(period):
                try period.validate()
                return period
            case let .days(days):
                // Validate logical keys before Foundation can normalize an invalid date.
                _ = try recordingPeriod()
                let start = days.lowerBound.startOfDay(in: calendar)
                let last = days.upperBound.startOfDay(in: calendar)
                guard let end = calendar.dateInterval(of: .day, for: last)?.end else {
                    throw RecordingDayCoverage.ValidationError.unavailableCalendarBoundary
                }
                return try RecordingPeriod(start: start, end: end)
        }
    }

    public func contains(_ entry: AttributedLocationSample, viewingCalendar: Calendar) -> Bool {
        switch self {
            case let .instants(period): period.contains(entry.sample.timestamp)
            case let .days(days): days.contains(entry.calendarDay(in: viewingCalendar))
        }
    }
}
