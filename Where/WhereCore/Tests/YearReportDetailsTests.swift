import RegionKit
import Testing
@testable import WhereCore

struct YearReportDetailsTests {
    @Test func retainsReportAndPrimaryRegionLocations() {
        let report = YearReport(year: 2026, days: [], totals: [.california: 1])
        let locations = [
            Region.california: [RegionDayLocations(
                day: CalendarDay(year: 2026, month: 4, day: 3),
                points: [RegionDayPoint(
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 12,
                )],
            )],
        ]

        let details = YearReportDetails(
            report: report,
            primaryRegionLocations: locations,
        )

        #expect(details.report == report)
        #expect(details.primaryRegionLocations == locations)
    }
}
