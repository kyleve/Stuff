import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the App Intents composition seams — `makeForIntents` (the GPS-free
/// stack an intent reads and writes through) and `forIntents(sharingStoreOf:)`
/// (the store-sharing stack the app's composition root derives from the
/// launch's services and installs into the intent layer) — driven against
/// in-memory stores.
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

/// `forIntents(sharingStoreOf:)` — the store-sharing stack the app installs
/// into the intent layer after launch. The store, attribution, and clock are
/// shared (a second container over the app's store file, racing creation on a
/// fresh install, is the regression this pins); only the location source
/// differs — the stack wires the idle source, so intents never start GPS.
struct WhereServicesForIntentsSharingTests {
    @Test func sharedStackRidesTheBaseServicesStore() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)

        let shared = WhereServices.forIntents(sharingStoreOf: base)

        #expect(shared.modelContainer != nil)
        #expect(shared.modelContainer === base.modelContainer)
        #expect(shared.modelContainer === store.inspectorContainer)
    }

    @Test func sharedStackStillNeverOffersALocationFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)

        let shared = WhereServices.forIntents(sharingStoreOf: base)

        #expect(await shared.ingestor.currentLocation() == nil)
    }

    @Test func writesThroughTheSharedStackAreVisibleToTheBase() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)
        let shared = WhereServices.forIntents(sharingStoreOf: base)

        try await shared.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00"),
            regions: [.california],
            audit: nil,
        )

        let report = try await base.reports.yearReport(for: 2026)
        #expect(report.totals[.california] == 1)
    }

    @Test func sharedStackInheritsTheBaseClock() async throws {
        // The derived stack rides the base's injected clock — day bucketing
        // and scan windows can't diverge from the layer it was derived from.
        let fixed = WhereCoreTestSupport.iso("2026-03-01T09:00:00-08:00")
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store, now: { fixed })

        let shared = WhereServices.forIntents(sharingStoreOf: base)

        #expect(shared.now() == fixed)
    }
}
