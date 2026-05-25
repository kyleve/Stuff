import Foundation

/// Aggregated presence for a whole year. Snapshot-friendly: days are
/// sorted ascending by date and totals are encoded as a string-keyed
/// JSON object (using `Region.rawValue`) so `JSONEncoder.sortedKeys`
/// produces deterministic output. Without this, Swift's default
/// `Codable` for `[Region: Int]` would emit an unkeyed array whose
/// element order follows `Dictionary` iteration and is not stable
/// across processes.
public struct YearReport: Hashable, Sendable {
    public let year: Int
    public let days: [DayPresence]
    public let totals: [Region: Int]

    public init(year: Int, days: [DayPresence], totals: [Region: Int]) {
        self.year = year
        self.days = days.sorted { $0.date < $1.date }
        self.totals = totals
    }
}

extension YearReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case year
        case days
        case totals
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(days, forKey: .days)
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: totals.map { ($0.key.rawValue, $0.value) },
        )
        try container.encode(stringKeyed, forKey: .totals)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let days = try container.decode([DayPresence].self, forKey: .days)
        let stringKeyed = try container.decode([String: Int].self, forKey: .totals)
        let regionKeyed: [Region: Int] = Dictionary(
            uniqueKeysWithValues: stringKeyed.compactMap { pair in
                Region(rawValue: pair.key).map { ($0, pair.value) }
            },
        )
        self.init(year: year, days: days, totals: regionKeyed)
    }
}
