import Foundation

/// A maximal run of consecutive calendar days that have no recorded presence —
/// e.g. "Jan 3 – Jan 7, 5 days". Used to surface logging gaps in the UI and to
/// drive the backfill flow.
public struct MissingDayRange: Hashable, Sendable, Identifiable {
    /// Start-of-day key of the first missing day in the run.
    public let start: Date
    /// Start-of-day key of the last missing day in the run.
    public let end: Date
    public let dayCount: Int

    public var id: Date {
        start
    }

    public init(start: Date, end: Date, dayCount: Int) {
        self.start = start
        self.end = end
        self.dayCount = dayCount
    }
}

/// Pure rules for finding the calendar days the user *should* have logged but
/// didn't. A day "counts as missed" when it falls in the inclusive window
/// `[Jan 1 of the year, through]` and has no `DayPresence`. No I/O.
public enum MissingDays {
    /// Start-of-day keys in `[Jan 1 of year, min(through, Dec 31 of year)]`
    /// (inclusive) that are absent from `present`.
    ///
    /// `present` should be the set of start-of-day keys that already have any
    /// recorded presence (GPS or manual). It is normalized to start-of-day in
    /// `calendar` defensively, so callers don't have to pre-normalize. Pass the
    /// same `calendar` (identifier + timezone) that produced the `present`
    /// keys, otherwise day boundaries won't line up.
    public static func missingDayKeys(
        year: Int,
        through: Date,
        present: Set<Date>,
        calendar: Calendar,
    ) -> [Date] {
        guard
            let firstOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let firstOfNextYear = calendar.date(
                from: DateComponents(year: year + 1, month: 1, day: 1),
            ),
            let lastOfYear = calendar.date(byAdding: .day, value: -1, to: firstOfNextYear)
        else { return [] }

        let start = calendar.startOfDay(for: firstOfYear)
        // Clamp the upper bound to this year so a `through` in a later year
        // doesn't pull next year's days into the result.
        let requested = calendar.startOfDay(for: through)
        let last = min(requested, calendar.startOfDay(for: lastOfYear))
        guard start <= last else { return [] }

        let normalizedPresent = Set(present.map { calendar.startOfDay(for: $0) })
        return start
            .calendarDays(through: last, in: calendar)
            .filter { !normalizedPresent.contains($0) }
    }

    /// Collapse a set of start-of-day keys into maximal consecutive runs,
    /// sorted ascending by start date. Keys are normalized and de-duplicated in
    /// `calendar` first, so adjacent calendar days fold into one range.
    public static func ranges(_ keys: [Date], calendar: Calendar) -> [MissingDayRange] {
        let sorted = Set(keys.map { calendar.startOfDay(for: $0) }).sorted()
        guard var runStart = sorted.first else { return [] }

        var previous = runStart
        var count = 1
        var result: [MissingDayRange] = []
        for date in sorted.dropFirst() {
            if isConsecutive(previous, date, calendar: calendar) {
                previous = date
                count += 1
            } else {
                result.append(MissingDayRange(start: runStart, end: previous, dayCount: count))
                runStart = date
                previous = date
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
    public static func backlogCutoff(asOf now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    /// Convenience: the missing days for a year, already collapsed into ranges.
    public static func missingRanges(
        year: Int,
        through: Date,
        present: Set<Date>,
        calendar: Calendar,
    ) -> [MissingDayRange] {
        let keys = missingDayKeys(
            year: year,
            through: through,
            present: present,
            calendar: calendar,
        )
        return ranges(keys, calendar: calendar)
    }

    private static func isConsecutive(
        _ previous: Date,
        _ candidate: Date,
        calendar: Calendar,
    ) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 1, to: previous) else { return false }
        return calendar.isDate(next, inSameDayAs: candidate)
    }
}
