import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the App Intents composition seams — `makeForIntents` (the GPS-free
/// stack an intent reads and writes through) and `forIntents(sharingStoreOf:)`
/// (the store-sharing stack the app's composition root installs after launch)
/// — driven against in-memory stores. The fallback `forIntents()` opens the
/// real App Group store, so it isn't exercised here.
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
/// into the intent layer after launch. Only the *store* is shared (a second
/// container over the app's store file, racing creation on a fresh install,
/// is the regression this pins); the stack still wires the idle location
/// source.
struct WhereServicesForIntentsSharingTests {
    @Test func sharedStackRidesTheBaseServicesStore() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)

        let shared = try await WhereServices.forIntents(sharingStoreOf: base)

        #expect(shared.modelContainer != nil)
        #expect(shared.modelContainer === base.modelContainer)
        #expect(shared.modelContainer === store.inspectorContainer)
    }

    @Test func sharedStackStillNeverOffersALocationFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)

        let shared = try await WhereServices.forIntents(sharingStoreOf: base)

        #expect(await shared.ingestor.currentLocation() == nil)
    }

    @Test func writesThroughTheSharedStackAreVisibleToTheBase() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)
        let shared = try await WhereServices.forIntents(sharingStoreOf: base)

        try await shared.journal.addManualDay(
            date: WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00"),
            regions: [.california],
            audit: nil,
        )

        let report = try await base.reports.yearReport(for: 2026)
        #expect(report.totals[.california] == 1)
    }
}
