import Foundation
import RegionKit
import WhereCore

/// Recorded points shared by primary and Elsewhere cards. Each installed snapshot
/// has a stable identity so artwork refreshes without comparing fixes in `body`.
struct RegionCardLocations {
    struct ID: Hashable {
        fileprivate let rawValue = UUID()
    }

    let id = ID()
    let pointsByRegion: [Region: [RegionDayPoint]]

    /// Elsewhere already applies corrections and manual overlays during resolution.
    init(report: ElsewhereReport) {
        pointsByRegion = Dictionary(uniqueKeysWithValues: report.regions.map {
            ($0.region, $0.locations.flatMap(\.points))
        })
    }

    init(details: YearReportDetails) {
        var filtered: [Region: [RegionDayPoint]] = [:]
        for (region, locations) in details.primaryRegionLocations {
            let creditedDays = Set(
                details.report.days
                    .filter { $0.regions.contains(region) }
                    .map(\.day),
            )
            let points = locations
                .filter { creditedDays.contains($0.day) }
                .flatMap(\.points)
            if points.isEmpty == false {
                filtered[region] = points
            }
        }
        pointsByRegion = filtered
    }
}
