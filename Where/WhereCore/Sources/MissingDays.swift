import Foundation

/// A maximal run of consecutive calendar days that have no recorded presence —
/// e.g. "Jan 3 – Jan 7, 5 days". Used to surface logging gaps in the UI and to
/// drive the backfill flow.
public struct MissingDayRange: Hashable, Sendable, Identifiable {
    /// The first missing day in the run.
    public let start: CalendarDay
    /// The last missing day in the run.
    public let end: CalendarDay
    public let dayCount: Int

    public var id: CalendarDay {
        start
    }

    public init(start: CalendarDay, end: CalendarDay, dayCount: Int) {
        self.start = start
        self.end = end
        self.dayCount = dayCount
    }
}

/// Pure rules for finding the calendar days the user *should* have logged but
/// didn't. A day "counts as missed" when it falls in the inclusive window
/// `[Jan 1 of the year, through]` and has no `DayPresence`. No I/O.
public enum MissingDays {
    /// The calendar days in `[Jan 1 of year, min(through, Dec 31 of year)]`
    /// (inclusive) that are absent from `present`.
    ///
    /// `present` is the set of days that already have any recorded presence
    /// (GPS or manual). All arguments are timezone-independent `CalendarDay`s,
    /// so this is pure calendar arithmetic with no time zone to line up.
    public static func missingDayKeys(
        year: Int,
        through: CalendarDay,
        present: Set<CalendarDay>,
    ) -> [CalendarDay] {
        let start = CalendarDay(year: year, month: 1, day: 1)
        // Clamp the upper bound to this year so a `through` in a later year
        // doesn't pull next year's days into the result.
        let last = min(through, CalendarDay(year: year, month: 12, day: 31))
        guard start <= last else { return [] }

        return start
            .days(through: last)
            .filter { !present.contains($0) }
    }

    /// Collapse a set of days into maximal consecutive runs, sorted ascending by
    /// start day. Keys are de-duplicated first, so adjacent calendar days fold
    /// into one range.
    public static func ranges(_ keys: [CalendarDay]) -> [MissingDayRange] {
        let sorted = Set(keys).sorted()
        guard var runStart = sorted.first else { return [] }

        var previous = runStart
        var count = 1
        var result: [MissingDayRange] = []
        for day in sorted.dropFirst() {
            if previous.adding(days: 1) == day {
                previous = day
                count += 1
            } else {
                result.append(MissingDayRange(start: runStart, end: previous, dayCount: count))
                runStart = day
                previous = day
                count = 1
            }
        }
        result.append(MissingDayRange(start: runStart, end: previous, dayCount: count))
        return result
    }

    /// The last day that counts toward the *backlog* of missed days as of
    /// `now`: the day before today. Today is still "pending" — the user can log
    /// it before the day ends — so it's surfaced by the forward-looking reminder
    /// rather than counted as already missed. Pass this as `through` for the
    /// badge / banner / backfill so they don't warn about today every morning.
    public static func backlogCutoff(asOf now: Date, calendar: Calendar) -> CalendarDay {
        CalendarDay(from: now, in: calendar).adding(days: -1)
    }

    /// Convenience: the missing days for a year, already collapsed into ranges.
    public static func missingRanges(
        year: Int,
        through: CalendarDay,
        present: Set<CalendarDay>,
    ) -> [MissingDayRange] {
        ranges(missingDayKeys(year: year, through: through, present: present))
    }
}
