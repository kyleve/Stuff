import Foundation

/// The set of regions the user was in on a particular calendar day.
///
/// `regions` is a `Set` because we want union semantics (a day in CA + NY
/// counts for both) but encoding writes a sorted array for deterministic
/// snapshots.
public struct DayPresence: Hashable, Sendable {
    /// Start-of-day in whichever calendar/timezone produced this value.
    public let date: Date
    public let regions: Set<Region>

    public init(date: Date, regions: Set<Region>) {
        self.date = date
        self.regions = regions
    }
}

extension DayPresence: Codable {
    private enum CodingKeys: String, CodingKey {
        case date
        case regions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(regions.sorted(), forKey: .regions)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(Date.self, forKey: .date)
        let regions = try container.decode([Region].self, forKey: .regions)
        self.init(date: date, regions: Set(regions))
    }
}
