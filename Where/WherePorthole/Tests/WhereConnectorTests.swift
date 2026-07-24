import Foundation
import PortholeCore
import PortholeKit
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WherePorthole

@MainActor
struct WhereConnectorTests {
    private func makeServices() async throws -> WhereServices {
        let store = try SwiftDataStore.inMemory()
        return try await WhereServices.make(store: store, locationSource: IdleLocationSource())
    }

    private func preferences() -> WherePreferencesSnapshot {
        WherePreferencesSnapshot(
            hasOnboarded: true,
            wantsTracking: true,
            remindersEnabled: false,
            summaryEnabled: false,
            issueAlertsEnabled: true,
            driftThresholdMeters: 500,
        )
    }

    private func source(
        _ connector: WhereConnector,
        _ id: PortholeDataSourceID,
    ) -> PortholeDataSource {
        connector.dataSources().first { $0.descriptor.id == id }!
    }

    private func action(_ connector: WhereConnector, _ id: PortholeActionID) -> PortholeAction {
        connector.actions().first { $0.descriptor.id == id }!
    }

    @Test func yearReportReflectsSeededManualDay() async throws {
        let services = try await makeServices()
        let date = Date(timeIntervalSince1970: 1_735_732_800) // 2025-01-01
        try await services.journal.addManualDay(date: date, regions: [.california], audit: nil)

        let connector = WhereConnector(services: services, preferences: preferences())
        let page = try await source(connector, "year-report")
            .fetch(PortholeQuery(filters: ["year": 2025]))
        let california = page.rows.first { $0["region"]?.stringValue == Region.california.rawValue }
        #expect(california != nil)
        #expect((california?["days"]?.intValue ?? 0) >= 1)
    }

    @Test func manualDaysSourceListsSeededDays() async throws {
        let services = try await makeServices()
        let date = Date(timeIntervalSince1970: 1_735_732_800)
        try await services.journal.addManualDay(date: date, regions: [.newYork], audit: nil)

        let connector = WhereConnector(services: services, preferences: preferences())
        let page = try await source(connector, "manual-days")
            .fetch(PortholeQuery(filters: ["year": 2025]))
        #expect(!page.rows.isEmpty)
        #expect(page.rows
            .contains {
                $0["regions"]?.arrayValue?.contains(.string(Region.newYork.rawValue)) == true
            })
    }

    @Test func preferencesSourceReflectsSnapshot() async throws {
        let services = try await makeServices()
        let connector = WhereConnector(services: services, preferences: preferences())
        let page = try await source(connector, "preferences").fetch(PortholeQuery())
        let row = try #require(page.rows.first)
        #expect(row["hasOnboarded"]?.boolValue == true)
        #expect(row["driftThresholdMeters"]?.intValue == 500)
    }

    @Test func dataIssuesSourceReturnsCategoryCounts() async throws {
        let services = try await makeServices()
        let connector = WhereConnector(services: services, preferences: preferences())
        let page = try await source(connector, "data-issues")
            .fetch(PortholeQuery(filters: ["year": 2025]))
        // Every category is represented (count may be zero).
        let categories = Set(page.rows.compactMap { $0["category"]?.stringValue })
        #expect(categories.contains("missingDays"))
    }

    @Test func scanDataIssuesActionReturnsCounts() async throws {
        let services = try await makeServices()
        let connector = WhereConnector(services: services, preferences: preferences())
        let result = try await action(connector, "scan-data-issues")
            .handler(.object(["year": 2025]))
        #expect(result["missingDays"]?.intValue != nil)
        #expect(result["borderDrift"]?.intValue != nil)
    }

    @Test func attributeCoordinateNamesTheRegion() async throws {
        let services = try await makeServices()
        let connector = WhereConnector(services: services, preferences: preferences())
        // A point in central California.
        let result = try await action(connector, "attribute-coordinate")
            .handler(.object(["latitude": 37.0, "longitude": -120.0]))
        #expect(result["region"]?.stringValue == Region.california.rawValue)
        #expect(result["name"]?.stringValue != nil)
    }

    @Test func captureLocationNowReturnsNullWithoutAFix() async throws {
        let services = try await makeServices()
        let connector = WhereConnector(services: services, preferences: preferences())
        let result = try await action(connector, "capture-location-now").handler(.object([:]))
        #expect(result == .null)
    }
}
