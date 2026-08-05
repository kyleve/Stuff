import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Exercises `BackupModel`'s export/import bridging: a successful round-trip
/// across two independent stores, a rolled-back failure, and the committed
/// cleanup-partial-success path that must preserve its import summary.
@MainActor
struct BackupModelTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    private func seed(_ services: WhereServices) async throws {
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
            audit: nil,
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
        try await services.journal.dismissIssue(
            id: .borderDrift(day: CalendarDay(year: 2026, month: 4, day: 1)),
        )
    }

    @Test func exportThenImportRoundTripsThroughTheModel() async throws {
        let sourceStore = try SwiftDataStore.inMemory()
        let source = WhereServices(store: sourceStore, locationSource: ScriptedLocationSource())
        try await seed(source)
        let sourceBackup = BackupModel(services: source)

        let url = try #require(await sourceBackup.exportBackup())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(sourceBackup.backupState == .idle)
        #expect(sourceBackup.backupError == nil)

        let destinationStore = try SwiftDataStore.inMemory()
        let destination = WhereServices(
            store: destinationStore,
            locationSource: ScriptedLocationSource(),
        )
        let destinationBackup = BackupModel(services: destination)

        let result = try #require(
            await destinationBackup.importBackup(from: url, strategy: .merge),
        )
        let summary = result.summary
        #expect(result == .imported(summary))
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)
        #expect(summary.dismissedIssueCount == 1)
        #expect(destinationBackup.backupState == .idle)

        // The committed result is also exposed on the model (not just returned),
        // so the confirmation alert survives the backup screen being popped
        // mid-import. Dismissing the result clears it.
        #expect(destinationBackup.lastImportSummary?.evidenceCount == summary.evidenceCount)
        #expect(destinationBackup.isShowingImportResult)
        destinationBackup.isShowingImportResult = false
        #expect(destinationBackup.lastImportSummary == nil)
        #expect(!destinationBackup.isShowingImportResult)

        #expect(try await destinationStore.allEvidence() == sourceStore.allEvidence())
        #expect(try await destinationStore.allManualDays() == sourceStore.allManualDays())
        #expect(
            try await destinationStore.dismissedIssueIDs() == sourceStore.dismissedIssueIDs(),
        )
    }

    @Test func importingABogusFileSetsBackupError() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        let backup = BackupModel(services: services)

        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try Data("not a backup".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        let summary = await backup.importBackup(from: bogus, strategy: .replace)
        #expect(summary == nil)
        #expect(backup.backupError != nil)
        #expect(backup.backupState == .idle)
        // A failed import must not surface a success confirmation.
        #expect(backup.lastImportSummary == nil)
        #expect(!backup.isShowingImportResult)
    }

    @Test func committedCleanupFailurePreservesSummaryAsPartialSuccess() async throws {
        let sourceStore = try SwiftDataStore.inMemory()
        let source = WhereServices(
            store: sourceStore,
            locationSource: ScriptedLocationSource(),
        )
        try await seed(source)
        let sourceBackup = BackupModel(services: source)
        let url = try #require(await sourceBackup.exportBackup())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let destinationStore = try SwiftDataStore.inMemory()
        let outbox = FailingClearLocationOutbox()
        let destination = WhereServices(
            store: destinationStore,
            locationSource: ScriptedLocationSource(),
            locationOutbox: outbox,
        )
        let backup = BackupModel(services: destination)

        let result = try #require(
            await backup.importBackup(from: url, strategy: .replace),
        )
        let summary = result.summary

        #expect(result == .committedWithCleanupFailure(summary))
        #expect(result.requiresCleanupRecovery)
        #expect(summary.evidenceCount == 1)
        #expect(summary.manualDayCount == 1)
        #expect(backup.lastImportResult == result)
        #expect(backup.lastImportSummary == summary)
        #expect(backup.isShowingImportResult)
        #expect(backup.backupError == nil)
        #expect(backup.backupState == .idle)
        #expect(backup.importRecoveryState == .cleanupRequired(summary))
        #expect(!backup.canImport)

        // The warning represents committed data, not a rolled-back operation.
        #expect(try await destinationStore.allEvidence().count == 1)
        #expect(try await destinationStore.allManualDays().count == 1)

        // Recreating the view model over the same long-lived coordinator cannot forget the
        // committed boundary. A second Replace is rejected before it can remove newer data.
        let recreated = BackupModel(services: destination)
        await recreated.refreshImportRecoveryState()
        #expect(recreated.importRecoveryState == .cleanupRequired(summary))
        #expect(!recreated.canImport)
        try await destination.journal.addManualDay(
            date: date(year: 2026, month: 4, day: 2),
            regions: [.newYork],
            audit: nil,
        )
        let rejected = await recreated.importBackup(from: url, strategy: .replace)
        #expect(rejected == .committedWithCleanupFailure(summary))
        #expect(try await destinationStore.allManualDays().count == 2)

        await outbox.setFailsToClear(false)
        await recreated.retryImportCleanup()

        #expect(recreated.importRecoveryState == .ready)
        #expect(recreated.canImport)
        #expect(recreated.backupError == nil)
    }
}

private actor FailingClearLocationOutbox: LocationOutbox {
    private var failsToClear = true

    func load() async throws -> [LocationOutboxEntry] {
        []
    }

    func save(_: [LocationOutboxEntry]) async throws {}
    func clear() async throws {
        guard !failsToClear else { throw CleanupFailure() }
    }

    func setFailsToClear(_ value: Bool) {
        failsToClear = value
    }
}

private struct CleanupFailure: Error {}
