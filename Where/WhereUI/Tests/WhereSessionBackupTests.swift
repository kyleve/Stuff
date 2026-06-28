import Foundation
import Testing
import WhereCore
@testable import WhereUI

/// Exercises `WhereSession`'s backup export/import bridging: a successful
/// round-trip across two independent stores, and the failure path that
/// surfaces `backupError` without leaving the session stuck "working".
@MainActor
struct WhereSessionBackupTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    private func seed(_ services: WhereServices) async throws {
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
        )
        try await services.journal.addEvidence(
            Evidence(
                kind: .boardingPass,
                capturedAt: date(year: 2026, month: 3, day: 1),
                region: .california,
                contentType: .pdf,
            ),
            blob: Data("boarding-pass".utf8),
        )
        try await services.journal.dismissIssue(key: "borderDrift:1700000000")
    }

    @Test func exportThenImportRoundTripsThroughTheSession() async throws {
        let sourceStore = try SwiftDataStore.inMemory()
        let source = WhereServices(store: sourceStore, locationSource: ScriptedLocationSource())
        try await seed(source)
        let sourceSession = WhereSession(services: source, selectedYear: 2026)

        let url = try #require(await sourceSession.exportBackup())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(sourceSession.backupState == .idle)
        #expect(sourceSession.backupError == nil)

        let destinationStore = try SwiftDataStore.inMemory()
        let destination = WhereServices(
            store: destinationStore,
            locationSource: ScriptedLocationSource(),
        )
        let destinationSession = WhereSession(services: destination, selectedYear: 2026)

        let summary = try #require(
            await destinationSession.importBackup(from: url, strategy: .merge),
        )
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)
        #expect(summary.dismissedIssueCount == 1)
        #expect(destinationSession.backupState == .idle)

        #expect(try await destinationStore.allEvidence() == sourceStore.allEvidence())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
        #expect(
            try await destinationStore.dismissedIssueKeys() == sourceStore.dismissedIssueKeys(),
        )
    }

    @Test func importingABogusFileSetsBackupError() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        let session = WhereSession(services: services, selectedYear: 2026)

        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try Data("not a backup".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        let summary = await session.importBackup(from: bogus, strategy: .replace)
        #expect(summary == nil)
        #expect(session.backupError != nil)
        #expect(session.backupState == .idle)
    }
}
