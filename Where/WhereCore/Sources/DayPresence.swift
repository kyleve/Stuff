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
    /// aggregator's own report-output days (which are never user entries) as
    /// well as manual records written before this field existed.
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

    private enum CodingKeys: String, CodingKey {
        case day
        case date
        case regions
        case isAuthoritative
        case audit
    }

    /// Custom decode so records and backup archives written before
    /// `isAuthoritative` / `audit` existed (v1 manifests, pre-existing manual
    /// days) decode as additive (non-authoritative) with no audit instead of
    /// failing on the missing keys, and so pre-`CalendarDay` manifests that
    /// stored an absolute `date` instant still import: the legacy instant is a
    /// start-of-day in the writer's zone, so we recover its calendar day (see
    /// `CalendarDay.init(recoveringLegacyStartOfDay:in:)`) using UTC — correct
    /// for continental writers; the on-device migration re-derives with the
    /// device calendar for the persisted store.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let calendarDay = try container.decodeIfPresent(CalendarDay.self, forKey: .day) {
            day = calendarDay
        } else {
            let legacyInstant = try container.decode(Date.self, forKey: .date)
            day = CalendarDay(
                recoveringLegacyStartOfDay: legacyInstant,
                in: Self.legacyRecoveryCalendar,
            )
        }
        regions = try container.decode(Set<Region>.self, forKey: .regions)
        isAuthoritative = try container
            .decodeIfPresent(Bool.self, forKey: .isAuthoritative) ?? false
        audit = try container.decodeIfPresent(ManualEntryAudit.self, forKey: .audit)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(regions, forKey: .regions)
        try container.encode(isAuthoritative, forKey: .isAuthoritative)
        try container.encodeIfPresent(audit, forKey: .audit)
    }

    /// UTC Gregorian calendar for the calendar-free legacy decode fallback.
    private static let legacyRecoveryCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
