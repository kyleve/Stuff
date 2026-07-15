import Foundation

/// Missing-day derivation for a loaded `YearReport`. These adapt the pure
/// `MissingDays` rules to a specific report + reference date, so callers (the
/// scene's year model, the calendar) read a one-liner instead of re-deriving
/// the present-day set and backlog cutoff themselves.
///
/// "Missing" is only meaningful for the *current* year: a past year can't gain
/// today's coverage, so these return empty for it. Today itself is excluded
/// (it's still loggable) via `MissingDays.backlogCutoff`.
extension YearReport {
    /// Whether this report's `year` is the calendar year containing `now`.
    public func isCurrentYear(asOf now: Date, calendar: Calendar) -> Bool {
        year == calendar.component(.year, from: now)
    }

    /// Calendar days in this report's year that still need logging as of `now`
    /// (Jan 1 through yesterday). Empty for a past year.
    public func missingDayKeys(asOf now: Date, calendar: Calendar) -> Set<CalendarDay> {
        guard isCurrentYear(asOf: now, calendar: calendar) else { return [] }
        return Set(MissingDays.missingDayKeys(
            year: year,
            through: MissingDays.backlogCutoff(asOf: now, calendar: calendar),
            present: Set(days.map(\.day)),
        ))
    }

    /// Unlogged days in this report's year (as of `now`), collapsed into
    /// consecutive ranges for the warning banner and backfill flow. Empty for a
    /// past year.
    public func missingDayRanges(asOf now: Date, calendar: Calendar) -> [MissingDayRange] {
        guard isCurrentYear(asOf: now, calendar: calendar) else { return [] }
        return MissingDays.missingRanges(
            year: year,
            through: MissingDays.backlogCutoff(asOf: now, calendar: calendar),
            present: Set(days.map(\.day)),
        )
    }

    /// Total number of unlogged days behind `missingDayRanges(asOf:calendar:)`.
    public func missingDayCount(asOf now: Date, calendar: Calendar) -> Int {
        missingDayRanges(asOf: now, calendar: calendar).reduce(0) { $0 + $1.dayCount }
    }
}
