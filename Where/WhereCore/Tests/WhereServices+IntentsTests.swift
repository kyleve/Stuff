import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the App Intents composition seam `WhereServices.makeForIntents` — the
/// GPS-free stack an intent reads and writes through. The public
/// `forIntents()` opens the real App Group store, so it isn't exercised here;
/// this drives the same wiring against an in-memory store.
struct WhereServicesIntentsTests {
    @Test func stackWritesThroughJournalAndReadsBackThroughReports() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices.makeForIntents(store: store)

        try await services.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00"),
            regions: [.california],
            audit: nil,
        )

        let report = try await services.reports.yearReport(for: 2026)
        #expect(report.totals[.california] == 1)
        #expect(report.days.first?.regions == [.california])
    }

    @Test func stackNeverOffersALocationFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices.makeForIntents(store: store)

        // The idle source backs the ingestor, so a manual entry made from an
        // intent honestly records "no captured location" rather than a fix.
        #expect(await services.ingestor.currentLocation() == nil)
    }
}
