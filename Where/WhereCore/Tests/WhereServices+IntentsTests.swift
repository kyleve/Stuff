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
    @Test func flightCorrectionAndLaterSameDayPresenceReachReportsWidgetsAndIntents() async throws {
        let h = try await SampleCorrectionTestSupport.completedFlight()
        let proposal = try await h.proposal()
        let result = try await h.coordinator.apply(proposal)
        guard case .applied = result else {
            Issue.record("The completed flight correction must apply")
            return
        }
        let later = FlightTrajectoryFixtures.sample(501, minutes: 240, east: 1505)
        try await h.store.perform { try await h.store.add(sample: later) }

        let expected = proposal.resultingRegions.union([.canada])
        let intents = WhereServices.forIntents(sharingStoreOf: h.services)
        let report = try await h.reader.yearReport(for: h.day.year)
        let intentReport = try await intents.reports.yearReport(for: h.day.year)
        let widget = try await h.widgets.snapshot(asOf: later.timestamp)
        #expect(report.days.first?.regions == expected)
        #expect(intentReport.days == report.days)
        #expect(widget.dayRegions == expected)
        #expect(widget.totals == report.totals)
        #expect(try await h.reader.manualDays(inYear: h.day.year).isEmpty)
        #expect(try await h.store.sampleAttributionRevisions(for: [later.id]).isEmpty)

        let maps = try await h.reader.locations(onDay: h.day)
        #expect(maps[.canada]?.map(\.coordinate) == [later.coordinate])
        let originalSamples = FlightTrajectoryFixtures.turningFlight().samples
        let excludedIDs = Set(proposal.edits.filter(\.replacementRegions.isEmpty).map(\.sampleID))
        let excludedCoordinates = Set(originalSamples.filter { excludedIDs.contains($0.id) }
            .map(\.coordinate))
        let mappedCoordinates = Set(maps.values.flatMap { $0.map(\.coordinate) })
        #expect(mappedCoordinates.isDisjoint(with: excludedCoordinates))
        #expect(try await h.reader.representativeCoordinates(for: h.day.year)[.canada] == later
            .coordinate)
        #expect(try await h.reader.locations(in: .canada, year: h.day.year).first?.points
            .map(\.coordinate) == [later.coordinate])
        #expect(try await h.store.allSamples().count == originalSamples.count + 1)
    }

    @Test func sharedStackRidesTheBaseServicesStore() async throws {
        let store = try SwiftDataStore.inMemory()
        let base = try await WhereServices.makeForIntents(store: store)

        let shared = WhereServices.forIntents(sharingStoreOf: base)

        #expect((shared.store as? SwiftDataStore) === store)
        #expect((base.store as? SwiftDataStore) === store)
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
