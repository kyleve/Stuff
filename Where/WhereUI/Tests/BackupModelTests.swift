import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Exercises `BackupModel`'s Settings-only export bridge and error presentation.
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

    @Test func exportBuildsAnArchiveThroughTheModel() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        try await seed(services)
        let backup = BackupModel(services: services)

        let url = try #require(await backup.exportBackup())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(backup.backupState == .idle)
        #expect(backup.backupError == nil)
        let archive = try BackupService().readArchive(at: url).archive
        #expect(archive.evidence.count == 1)
        #expect(archive.manualDays.count == 1)
        #expect(archive.dismissedIssues.count == 1)
    }

    @Test func presentedErrorDrivesAndClearsTheAlert() throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        let backup = BackupModel(services: services)

        backup.presentBackupError(CleanupFailure())
        #expect(backup.backupError != nil)
        #expect(backup.isShowingBackupError)

        backup.isShowingBackupError = false
        #expect(backup.backupError == nil)
        #expect(!backup.isShowingBackupError)
    }
}

private struct CleanupFailure: Error {}
