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
    static var whereIntents: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
