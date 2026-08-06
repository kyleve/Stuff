import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
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

    /// A second GPS fix on an already-credited day leaves `YearReport` equal,
    /// but the store-change revision must re-key the raw-location load so the
    /// card constellation gains the new point without recreating the view.
    @Test func locationOnlyStoreChangeRekeysAndReloadsConstellation() async throws {
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: preferences,
        )
        let first = LocationSample(
            timestamp: Self.date(hour: 9),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 12,
            source: .gpsSignificantChange,
        )
        let second = LocationSample(
            timestamp: Self.date(hour: 13),
            coordinate: Coordinate(latitude: 37.7751, longitude: -122.4196),
            horizontalAccuracy: 8,
            source: .gpsSignificantChange,
        )

        try await services.journal.ingest(first)
        await report.refresh()
        report.observeDataChanges()
        let initialReport = try #require(report.report)
        let initialLoadID = PrimaryRegionLocationModel.LoadID(report: report)
        let model = PrimaryRegionLocationModel()
        await model.load(regions: initialLoadID.regions, from: report)
        #expect(model.pointsByRegion[.california]?.count == 1)

        try await services.journal.ingest(second)
        await waitForRevision {
            report.dataChangeRevision > initialLoadID.dataChangeRevision
        }

        #expect(report.report == initialReport)
        let refreshedLoadID = PrimaryRegionLocationModel.LoadID(report: report)
        #expect(refreshedLoadID != initialLoadID)
        await model.load(regions: refreshedLoadID.regions, from: report)
        #expect(model.pointsByRegion[.california]?.count == 2)
    }

    private func waitForRevision(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "store-change revision was not published before timeout")
    }

    private static func date(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 15,
            hour: hour,
        ))!
    }
}
