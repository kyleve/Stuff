import Foundation
import RegionKit
import WhereCore

/// A region paired with the number of calendar days the user was present in
/// it during a year. A small named struct rather than a tuple, per the
/// repo's value-type conventions.
public struct RegionDays: Hashable, Sendable, Identifiable {
    public let region: Region
    public let days: Int

    public var id: Region {
        region
    }

    public init(region: Region, days: Int) {
        self.region = region
        self.days = days
    }
}

/// Splits a `YearReport` into "primary" (the regions you spend the most days
/// in) and "secondary" (everywhere else you turned up). This is a
/// presentation concept — the domain layer only knows day counts — so it
/// lives in `WhereUI`.
public struct RegionRanking: Hashable, Sendable {
    /// How many top-ranked regions are treated as "primary".
    public static let primaryCount = 2

    public let primary: [RegionDays]
    public let secondary: [RegionDays]

    public init(primary: [RegionDays], secondary: [RegionDays]) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Build a ranking from a report. Regions with zero days are dropped.
    /// `.other` is never "primary" (it's a catch-all bucket, not a place you
    /// live), so it always falls into `secondary` when present.
    public init(report: YearReport, primaryCount: Int = RegionRanking.primaryCount) {
        let ranked = RegionRanking.ranked(report: report)
        let primary = Array(
            ranked.filter { $0.region != .other }.prefix(max(0, primaryCount)),
        )
        let primaryRegions = Set(primary.map(\.region))
        let secondary = ranked.filter { !primaryRegions.contains($0.region) }
        self.init(primary: primary, secondary: secondary)
    }

    /// All present regions sorted by day count descending, ties broken by
    /// `Region.allCases` declaration order so the layout is stable.
    static func ranked(report: YearReport) -> [RegionDays] {
        Region.rankedByDayCount(
            report.totals
                .filter { $0.value > 0 }
                .map { RegionDays(region: $0.key, days: $0.value) },
            days: \.days,
            region: \.region,
        )
    }

    public var isEmpty: Bool {
        primary.isEmpty && secondary.isEmpty
    }
}
