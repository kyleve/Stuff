import PeriscopeCore

/// Names `PresenceCalendar`'s timed spans, and nothing else — layout throws its
/// failures to the caller (`CalendarView` renders them), so what's worth
/// recording here is the cost.
///
/// A span-only facade: `private init()` leaves no way to construct one, so
/// "emit a `PresenceCalendarLog`" is unspellable and the type can only ever name
/// a scope and its spans. (It can't be an uninhabited enum — `LogEvent` is
/// `Codable`, which the compiler won't synthesize for one.)
@LogScope("PresenceCalendar")
enum PresenceCalendarLog {
    /// Names the layout spans (`log.measure(.layoutYear) { … }`).
    enum SpanName: Hashable {
        /// Laying out a whole year's month grids. Pure CPU on an already-loaded
        /// report, and it runs on the main actor from the calendar's `.task`, so
        /// it's worth watching even though it touches no disk. Individual months
        /// aren't spanned: twelve nested spans per layout would cost more to
        /// record than they'd explain.
        case layoutYear
    }
}
