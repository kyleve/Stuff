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

        let task = backup.prepareExport()
        await task.value
        guard case let .ready(url) = backup.exportState else {
            Issue.record("A completed export must publish its ready archive URL.")
            return
        }
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let archive = try BackupService().readArchive(at: url).archive
        #expect(archive.evidence.count == 1)
        #expect(archive.manualDays.count == 1)
        #expect(archive.dismissedIssues.count == 1)
    }

    @Test func failedExportPublishesOneHonestTerminalState() async {
        let exporter = ScriptedBackupExporter(behavior: .failed)
        let backup = BackupModel(exporter: exporter)

        await backup.prepareExport().value
        #expect(backup.exportState == .failed(message: "Archive could not be prepared."))

        backup.resetExport()
        #expect(backup.exportState == .idle)
    }

    @Test func cancellationCannotPublishLateReadiness() async {
        let exporter = ScriptedBackupExporter(behavior: .suspended)
        let backup = BackupModel(exporter: exporter)
        let task = backup.prepareExport()

        await exporter.waitUntilStarted()
        backup.cancelExport()
        await task.value

        #expect(backup.exportState == .idle)
        #expect(await exporter.discardCount == 0)
    }
}

private actor ScriptedBackupExporter: BackupExporting {
    enum Behavior {
        case failed
        case suspended
    }

    let behavior: Behavior
    private(set) var discardCount = 0
    private var started = false
    private let suspension: AsyncStream<Void>
    private let suspensionContinuation: AsyncStream<Void>.Continuation

    init(behavior: Behavior) {
        self.behavior = behavior
        (suspension, suspensionContinuation) = AsyncStream.makeStream()
    }

    func exportBackup(onProgress: @Sendable (Double) -> Void) async throws -> URL {
        started = true
        onProgress(0.42)
        switch behavior {
            case .failed:
                throw CleanupFailure()
            case .suspended:
                for await _ in suspension {}
                try Task.checkCancellation()
                return URL(fileURLWithPath: "/tmp/late-backup.zip")
        }
    }

    func discardExport() {
        discardCount += 1
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    deinit {
        suspensionContinuation.finish()
    }
}

private struct CleanupFailure: LocalizedError {
    var errorDescription: String? {
        "Archive could not be prepared."
    }
}
