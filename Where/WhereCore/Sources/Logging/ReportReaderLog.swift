import PeriscopeCore

/// Names `ReportReader`'s timed spans, and nothing else.
///
/// The reader has no events to emit — every failure it meets is thrown to the
/// caller, which decides how to surface it — so this type exists purely to give
/// the read path its own log scope and a compiler-checked set of span names.
/// A span-only facade, like ``PresenceCalendarLog``: `private init()` leaves no
/// way to construct one, so it can never be emitted as an event.
struct ReportReaderLog: LogEvent {
    /// Names the read spans (`log.measure(.yearReport) { … }`). Each is one store
    /// fetch plus the aggregation over it; the fetch itself is spanned separately
    /// by `SwiftDataStore`, so the difference between the two is compute.
    enum SpanName: Hashable {
        /// The workhorse: a year's samples + manual days, aggregated.
        case yearReport
        /// The single-read bundle a data-issue scan needs.
        case dataIssueReads
        /// A year of coordinates inside one region, grouped by day.
        case regionLocations
        /// One day's coordinates, grouped by the region they attribute to.
        case dayLocations
        /// One representative coordinate per region for a year.
        case representativeCoordinates
    }

    static let eventName = "ReportReader"

    var message: String {
        ""
    }

    private init() {}
}
