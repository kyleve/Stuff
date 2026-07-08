import Foundation
import RegionKit

/// The set of regions the user was in on a particular calendar day.
///
/// `regions` is a `Set` because we want union semantics (a day in CA + NY
/// counts for both).
public struct DayPresence: Hashable, Sendable, Codable {
    /// Start-of-day in whichever calendar/timezone produced this value.
    public let date: Date
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
        date: Date,
        regions: Set<Region>,
        isAuthoritative: Bool = false,
        audit: ManualEntryAudit? = nil,
    ) {
        self.date = date
        self.regions = regions
        self.isAuthoritative = isAuthoritative
        self.audit = audit
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case regions
        case isAuthoritative
        case audit
    }

    /// Custom decode so records and backup archives written before
    /// `isAuthoritative` / `audit` existed (v1 manifests, pre-existing manual
    /// days) decode as additive (non-authoritative) with no audit instead of
    /// failing on the missing keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        regions = try container.decode(Set<Region>.self, forKey: .regions)
        isAuthoritative = try container
            .decodeIfPresent(Bool.self, forKey: .isAuthoritative) ?? false
        audit = try container.decodeIfPresent(ManualEntryAudit.self, forKey: .audit)
    }
}
