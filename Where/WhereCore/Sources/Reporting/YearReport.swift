import Foundation
import RegionKit

/// Aggregated presence for a whole year. Days are sorted ascending by calendar
/// day on init so callers (and the per-month rollup test helpers) can rely on a
/// stable ordering.
public struct YearReport: Hashable, Sendable {
    public let year: Int
    public let days: [DayPresence]
    public let totals: [Region: Int]
    public let completeness: HistoryCompleteness

    public init(year: Int, days: [DayPresence], totals: [Region: Int]) {
        self.init(year: year, days: days, totals: totals, completeness: .foundation)
    }

    public init(
        year: Int,
        days: [DayPresence],
        totals: [Region: Int],
        completeness: HistoryCompleteness,
    ) {
        self.year = year
        self.days = days.sorted { $0.day < $1.day }
        self.totals = totals
        self.completeness = completeness
    }
}
