import Foundation
import RegionKit

/// The set of regions the user was in on a particular calendar day.
///
/// `regions` is a `Set` because we want union semantics (a day in CA + NY
/// counts for both).
public struct DayPresence: Hashable, Sendable, Codable {
    /// The timezone-independent calendar day this presence is for — the stable
    /// identity used for persistence, detection, and day matching. Resolve a
    /// concrete instant only when needed via `startOfDay(in:)`.
    public let day: CalendarDay
    public let regions: Set<Region>

    /// Whether this record *replaces* the GPS-derived regions for its day (a
    /// user correction) rather than *unioning* with them (a backfill). Only
    /// meaningful for manual-day records consumed by `DayAggregator.report`;
    /// the aggregator's own report-output days always leave it `false`.
    public let isAuthoritative: Bool

    /// Audit metadata for a *user-made* entry: when it was made, why, and where
    /// the device was at the time. `nil` for GPS-derived days and the
    /// aggregator's own report-output days (which are never user entries).
    public let audit: ManualEntryAudit?

    public init(
        day: CalendarDay,
        regions: Set<Region>,
        isAuthoritative: Bool = false,
        audit: ManualEntryAudit? = nil,
    ) {
        self.day = day
        self.regions = regions
        self.isAuthoritative = isAuthoritative
        self.audit = audit
    }

    /// Convenience for producers that hold a `Date` and the calendar that
    /// produced it (the aggregator, `DayJournal`, tests): pins the day to that
    /// date's components in `calendar`.
    public init(
        date: Date,
        in calendar: Calendar,
        regions: Set<Region>,
        isAuthoritative: Bool = false,
        audit: ManualEntryAudit? = nil,
    ) {
        self.init(
            day: CalendarDay(from: date, in: calendar),
            regions: regions,
            isAuthoritative: isAuthoritative,
            audit: audit,
        )
    }

    /// The first instant of this day in `calendar`, for callers that need a
    /// concrete `Date` (grid layout, sorting, display formatting).
    public func startOfDay(in calendar: Calendar) -> Date {
        day.startOfDay(in: calendar)
    }
}
