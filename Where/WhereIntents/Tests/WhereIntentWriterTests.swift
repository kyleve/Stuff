import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereIntents

/// The write seam the action intents delegate to: proves logging commits
/// through `DayJournal` with a "Logged with Siri" audit and no captured
/// location, and that a trip backfill's reported count matches what's written.
struct WhereIntentWriterTests {
    private func writer(_ services: WhereServices) -> WhereIntentWriter {
        WhereIntentWriter(services: services, calendar: IntentTestSupport.calendar())
    }

    @Test func logDayCommitsAManualDayWithSiriAuditAndNoLocation() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        try await writer(services).logDay(
            date: IntentTestSupport.iso("2026-06-15T12:00:00-07:00"),
            regions: [.california],
        )

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.totals[.california] == 1)

        // The audit is stripped from the aggregated report, so read the raw
        // manual record to confirm how it was stamped.
        let manual = try #require(await store.allManualDays().first)
        #expect(manual.audit?.note == IntentStrings.manualEntryNote)
        #expect(manual.audit?.location == nil)
    }

    @Test func logTripBackfillsInclusiveRangeAndReturnsCount() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let count = try await writer(services).logTrip(
            from: IntentTestSupport.iso("2026-02-10T09:00:00-08:00"),
            through: IntentTestSupport.iso("2026-02-14T20:00:00-08:00"),
            regions: [.newYork],
        )

        #expect(count == 5)
        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.totals[.newYork] == 5)
        #expect(report.days.allSatisfy { $0.regions == [.newYork] })
    }

    @Test func logTripWithInvertedRangeWritesNothing() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = IntentTestSupport.services(store: store)
        let count = try await writer(services).logTrip(
            from: IntentTestSupport.iso("2026-02-14T00:00:00-08:00"),
            through: IntentTestSupport.iso("2026-02-10T00:00:00-08:00"),
            regions: [.california],
        )

        #expect(count == 0)
        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.days.isEmpty)
    }
}
