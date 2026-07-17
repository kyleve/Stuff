import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the App Intents composition seam `WhereServices.makeForIntents` — the
/// GPS-free stack an intent reads and writes through — driven against an
/// in-memory store. The public `forIntents()` resolves the process's canonical
/// store (in-memory under tests); its sharing behavior is pinned by the
/// serialized `WhereServicesForIntentsCanonicalTests` below.
struct WhereServicesIntentsTests {
    @Test func stackWritesThroughJournalAndReadsBackThroughReports() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = try await WhereServices.makeForIntents(store: store)

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
        let services = try await WhereServices.makeForIntents(store: store)

        // The idle source backs the ingestor, so a manual entry made from an
        // intent honestly records "no captured location" rather than a fix.
        #expect(await services.ingestor.currentLocation() == nil)
    }
}

/// `forIntents()` must build over the process's *canonical* store — the same
/// instance the app's launch opens — never a second container over the same
/// store file (the fresh-install creation race this pins). Serialized because
/// the canonical vendor is process-global state; each test resets it around
/// its body, and under tests `Storage.default` is `.inMemory`, so nothing here
/// touches disk.
@Suite(.serialized)
struct WhereServicesForIntentsCanonicalTests {
    @Test func forIntentsSharesTheCanonicalStore() async throws {
        await SwiftDataStore.resetCanonicalForTesting()
        let canonical = try await SwiftDataStore.canonical()
        let first = try await WhereServices.forIntents()
        let second = try await WhereServices.forIntents()
        #expect(first.modelContainer === canonical.inspectorContainer)
        #expect(second.modelContainer === canonical.inspectorContainer)
        await SwiftDataStore.resetCanonicalForTesting()
    }

    @Test func forIntentsOpensTheCanonicalStoreWhenItGoesFirst() async throws {
        // An intent can fire before the app's open-store step (e.g. a Siri
        // invocation launching the process); whoever resolves first creates
        // the store, and the launch then reuses it.
        await SwiftDataStore.resetCanonicalForTesting()
        let services = try await WhereServices.forIntents()
        let canonical = try await SwiftDataStore.canonical()
        #expect(services.modelContainer === canonical.inspectorContainer)
        await SwiftDataStore.resetCanonicalForTesting()
    }
}
