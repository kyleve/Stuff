import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct PrimaryRegionLocationsTests {
    @Test func keepsRequestedRegionPointsOnlyOnCreditedDays() {
        let creditedDay = CalendarDay(year: 2026, month: 2, day: 1)
        let relabeledDay = CalendarDay(year: 2026, month: 7, day: 1)
        let creditedPoint = RegionDayPoint(
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 20,
        )
        let relabeledPoint = RegionDayPoint(
            coordinate: Coordinate(latitude: 34.0522, longitude: -118.2437),
            horizontalAccuracy: 30,
        )
        let details = YearReportDetails(
            report: YearReport(
                year: 2026,
                days: [
                    DayPresence(day: creditedDay, regions: [.california]),
                    DayPresence(day: relabeledDay, regions: [.newYork]),
                ],
                totals: [.california: 1, .newYork: 1],
            ),
            primaryRegionLocations: [
                .california: [
                    RegionDayLocations(day: creditedDay, points: [creditedPoint]),
                    RegionDayLocations(day: relabeledDay, points: [relabeledPoint]),
                ],
            ],
        )

        let locations = PrimaryRegionLocations(details: details)

        #expect(locations.pointsByRegion == [.california: [creditedPoint]])
    }

    /// A second GPS fix on an already-credited day leaves `YearReport` equal,
    /// but the production store-change flow installs different year details and
    /// updates the constellation without recreating the view.
    @Test func locationOnlyStoreChangeRefreshesConstellationDetails() async throws {
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
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
        await report.activate()
        defer { report.deactivate() }
        let initialReport = try #require(report.report)
        let initialLocations = try #require(report.primaryRegionLocations)
        #expect(initialLocations.pointsByRegion[.california]?.count == 1)

        try await services.journal.ingest(second)
        await waitUntil {
            report.primaryRegionLocations?.pointsByRegion[.california]?.count == 2
        }

        #expect(report.report == initialReport)
        let refreshedLocations = try #require(report.primaryRegionLocations)
        #expect(refreshedLocations.id != initialLocations.id)
        #expect(refreshedLocations.pointsByRegion[.california]?.count == 2)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "location details were not refreshed before timeout")
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
