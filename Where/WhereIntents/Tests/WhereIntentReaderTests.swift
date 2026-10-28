import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// The read seam the query intents delegate to, driven against an in-memory
/// store seeded through `DayJournal`.
struct WhereIntentReaderTests {
    private func reader(_ services: WhereServices, now: @escaping @Sendable () -> Date = { Date() })
        -> WhereIntentReader
    {
        WhereIntentReader(services: services, calendar: IntentTestSupport.calendar(), now: now)
    }

    @Test func dayCountReflectsYearReportTotals() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-01T12:00:00-08:00"),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-02T12:00:00-08:00"),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: IntentTestSupport.iso("2026-03-03T12:00:00-08:00"),
            regions: [.newYork],
            audit: nil,
        )

        let reader = reader(services)
        #expect(try await reader.dayCount(in: .california, year: 2026) == 2)
        #expect(try await reader.dayCount(in: .newYork, year: 2026) == 1)
        #expect(try await reader.dayCount(in: .canada, year: 2026) == 0)
    }

    @Test func regionsOnDateReturnsThatDaysRegions() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let day = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        try await services.journal.addManualDay(
            date: day,
            regions: [.california, .newYork],
            audit: nil,
        )

        let regions = try await reader(services).regions(on: day)
        #expect(regions == [.california, .newYork])
    }

    @Test func regionsOnAnUnloggedDayAreEmpty() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let regions = try await reader(services)
            .regions(on: IntentTestSupport.iso("2026-06-15T12:00:00-07:00"))
        #expect(regions.isEmpty)
    }

    @Test func todayRegionsUsesTheWidgetSnapshotFastPath() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let calendar = IntentTestSupport.calendar()
        let today = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        // Snapshot describing today wins without any store read.
        var reader = reader(services, now: { today })
        reader.todaySnapshot = {
            WidgetSnapshot(
                day: calendar.startOfDay(for: today),
                year: 2026,
                dayRegions: [.canada],
                totals: [:],
            )
        }
        #expect(try await reader.todayRegions() == [.canada])
    }

    @Test func todayRegionsFallsBackToTheStoreWithoutASnapshot() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let today = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        try await services.journal.addManualDay(date: today, regions: [.california], audit: nil)

        var reader = reader(services, now: { today })
        reader.todaySnapshot = { nil }
        #expect(try await reader.todayRegions() == [.california])
    }

    @Test func todayRegionsIgnoresAStaleSnapshotFromAnotherDay() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let calendar = IntentTestSupport.calendar()
        let today = IntentTestSupport.iso("2026-06-15T12:00:00-07:00")
        try await services.journal.addManualDay(date: today, regions: [.newYork], audit: nil)

        var reader = reader(services, now: { today })
        // Snapshot is from yesterday, so the reader must fall back to the store.
        reader.todaySnapshot = {
            WidgetSnapshot(
                day: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))!,
                year: 2026,
                dayRegions: [.canada],
                totals: [:],
            )
        }
        #expect(try await reader.todayRegions() == [.newYork])
    }
}
