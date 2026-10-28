import Foundation

extension Calendar {
    /// The calendar the App Intents layer uses for all year/day math.
    ///
    /// It must match the one `WhereServices.forIntents()` aggregates reports in
    /// — `DayAggregator()`'s default, i.e. **Gregorian in the current time
    /// zone** — so a spoken "this year" / "on June 3" lines up with the stored
    /// data. Deriving the year from `Calendar.current` instead would break for
    /// anyone whose device calendar is non-Gregorian (a Buddhist-calendar
    /// device reports year ~2569, yielding an empty report). The
    /// `Calendar+WhereIntentsTests` drift guard pins this to `DayAggregator()`.
    ///
    /// A `let` captures the time zone once (at first use), which is fine: intent
    /// processes are short-lived, and `DayAggregator()` likewise snapshots
    /// `.current` when it's built — so the two stay aligned within a run.
    static let whereIntents: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
}
