import Foundation

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

    public init(date: Date, regions: Set<Region>, isAuthoritative: Bool = false) {
        self.date = date
        self.regions = regions
        self.isAuthoritative = isAuthoritative
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case regions
        case isAuthoritative
    }

    /// Custom decode so records and backup archives written before
    /// `isAuthoritative` existed (v1 manifests, pre-existing manual days)
    /// decode as additive (non-authoritative) instead of failing on the
    /// missing key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        regions = try container.decode(Set<Region>.self, forKey: .regions)
        isAuthoritative = try container
            .decodeIfPresent(Bool.self, forKey: .isAuthoritative) ?? false
    }
}
