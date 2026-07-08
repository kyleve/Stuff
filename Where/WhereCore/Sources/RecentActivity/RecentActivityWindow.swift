import Foundation

/// The look-back range a recent-activity summary covers. `day`, `week`, and
/// `month` are rolling look-backs ending at "now"; `yearToDate` runs from the
/// start of the current calendar year to now. Modeled as a typed, exhaustive
/// enum (not a raw `TimeInterval`) so the calendar-relative "year so far"
/// window can't be confused with a fixed span and every window is enumerable
/// for a picker.
public enum RecentActivityWindow: Sendable, Hashable, CaseIterable {
    case day
    case week
    case month
    case yearToDate

    /// The date interval this window covers, ending at `now`. Rolling windows
    /// subtract a fixed span; `yearToDate` starts at the first instant of
    /// `now`'s calendar year. The interval is always non-empty for `yearToDate`
    /// (year start never follows `now`).
    public func interval(now: Date, calendar: Calendar) -> DateInterval {
        switch self {
            case .day:
                DateInterval(start: now.addingTimeInterval(-Self.secondsPerDay), end: now)
            case .week:
                DateInterval(start: now.addingTimeInterval(-7 * Self.secondsPerDay), end: now)
            case .month:
                DateInterval(start: now.addingTimeInterval(-30 * Self.secondsPerDay), end: now)
            case .yearToDate:
                DateInterval(start: Self.startOfYear(for: now, calendar: calendar), end: now)
        }
    }

    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    /// First instant of `now`'s calendar year. A calendar that can't resolve a
    /// year from a date is a misconfiguration, not a user failure, so debug
    /// traps and release falls back to `now` (a zero-length window that reads
    /// as "nothing tracked" rather than crashing shipping code).
    private static func startOfYear(for now: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year], from: now)
        guard let start = calendar.date(from: components) else {
            assertionFailure("Calendar could not resolve the start of year for \(now)")
            return now
        }
        return start
    }
}
