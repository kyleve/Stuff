import RegionKit
import Testing
import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct PrimaryRegionLocationModelTests {
    @Test func loadsRequestedRegionsAndDropsDaysNoLongerCreditedToThem() async {
        let report = PreviewSupport.loadedYearReportModel()
        let creditedPoint = RegionDayPoint(
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 20,
        )
        let relabeledPoint = RegionDayPoint(
            coordinate: Coordinate(latitude: 34.0522, longitude: -118.2437),
            horizontalAccuracy: 30,
        )
        report.setLocations([
            .california: [
                RegionDayLocations(
                    day: CalendarDay(year: 2026, month: 2, day: 1),
                    points: [creditedPoint],
                ),
                RegionDayLocations(
                    day: CalendarDay(year: 2026, month: 7, day: 1),
                    points: [relabeledPoint],
                ),
            ],
            .newYork: [RegionDayLocations(
                day: CalendarDay(year: 2026, month: 7, day: 1),
                points: [relabeledPoint],
            )],
        ])
        let model = PrimaryRegionLocationModel()

        await model.load(regions: [.california], from: report)

        #expect(model.pointsByRegion == [.california: [creditedPoint]])
        #expect(model.revision == 2)
    }
}
