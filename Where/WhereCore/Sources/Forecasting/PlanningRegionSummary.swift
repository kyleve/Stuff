import Foundation
import RegionKit

/// Explicit and assumed days in a displayed range. These independent bounds
/// preserve their provenance and must not be added endpoint by endpoint.
public struct PlanningRegionSummary: Hashable, Sendable, Identifiable {
    public let region: Region
    public let plannedDays: DayBounds
    public let homeDays: DayBounds

    public var id: Region {
        region
    }

    public init(region: Region, plannedDays: DayBounds, homeDays: DayBounds) {
        self.region = region
        self.plannedDays = plannedDays
        self.homeDays = homeDays
    }
}

extension PlanningSnapshot {
    /// Summarize unique future days per region, retaining explicit-plan and
    /// raw Home-assumption bounds even when their effective coverage is certain.
    public func regionSummaries(
        in range: ClosedRange<CalendarDay>,
        asOf today: CalendarDay,
    ) -> [PlanningRegionSummary] {
        let start = max(range.lowerBound, today.adding(days: 1))
        guard start <= range.upperBound else { return [] }
        var counts: [Region: RegionSummaryCounts] = [:]
        for day in start.days(through: range.upperBound) {
            let presence = plannedPresence(on: day, asOf: today)
            for region in presence.possibleRegions {
                counts[region, default: RegionSummaryCounts()].plannedPossible += 1
                if presence.certainRegions.contains(region) {
                    counts[region, default: RegionSummaryCounts()].plannedCertain += 1
                }
            }
            if let home = presence.homeAssumption {
                counts[home.region, default: RegionSummaryCounts()].homePossible += 1
                if home.certainty == .certain {
                    counts[home.region, default: RegionSummaryCounts()].homeCertain += 1
                }
            }
        }
        return counts.map { region, count in
            PlanningRegionSummary(
                region: region,
                plannedDays: DayBounds(lower: count.plannedCertain, upper: count.plannedPossible),
                homeDays: DayBounds(lower: count.homeCertain, upper: count.homePossible),
            )
        }.sorted {
            Region.declarationOrder[$0.region, default: 0]
                < Region.declarationOrder[$1.region, default: 0]
        }
    }

    /// Accumulation stays per region so explicit and Home counts cannot drift
    /// into separate region collections. A row is created only for a possible day.
    private struct RegionSummaryCounts {
        var plannedCertain = 0
        var plannedPossible = 0
        var homeCertain = 0
        var homePossible = 0
    }
}
