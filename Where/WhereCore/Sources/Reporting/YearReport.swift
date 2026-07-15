import Foundation
import RegionKit

/// Aggregated presence for a whole year. Days are sorted ascending by calendar
/// day on init so callers (and the per-month rollup test helpers) can rely on a
/// stable ordering.
public struct YearReport: Hashable, Sendable {
    public let year: Int
    public let days: [DayPresence]
    public let totals: [Region: Int]

    public init(year: Int, days: [DayPresence], totals: [Region: Int]) {
        self.year = year
        self.days = days.sorted { $0.day < $1.day }
        self.totals = totals
    }
}
