import Observation
import RegionKit
import WhereCore

/// View-scoped GPS constellation state for the Locations card surface.
@MainActor
@Observable
final class PrimaryRegionLocationModel {
    private(set) var pointsByRegion: [Region: [RegionDayPoint]] = [:]
    private(set) var revision = 0

    func load(regions: [Region], from report: YearReportModel) async {
        pointsByRegion = [:]
        revision += 1

        let requested = Set(regions)
        guard requested.isEmpty == false else { return }
        let locations = await report.locations(in: requested)
        guard Task.isCancelled == false else { return }

        var filtered: [Region: [RegionDayPoint]] = [:]
        for region in regions {
            let creditedDays = Set(report.days(in: region).map(\.day))
            let points = locations[region, default: []]
                .filter { creditedDays.contains($0.day) }
                .flatMap(\.points)
            if points.isEmpty == false {
                filtered[region] = points
            }
        }
        guard Task.isCancelled == false else { return }
        pointsByRegion = filtered
        revision += 1
    }
}
