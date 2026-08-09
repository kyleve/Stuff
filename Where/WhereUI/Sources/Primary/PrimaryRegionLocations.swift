import Foundation
import RegionKit
import WhereCore

/// Render-ready recorded points for the Locations card surface. Its identity is
/// minted only when a different ``YearReportDetails`` value is installed, so
/// cards can restart projection without comparing a year's fixes in `body`.
struct PrimaryRegionLocations {
    struct ID: Hashable {
        fileprivate let rawValue = UUID()
    }

    let id = ID()
    let pointsByRegion: [Region: [RegionDayPoint]]

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
