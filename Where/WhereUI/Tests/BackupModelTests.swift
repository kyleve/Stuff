import AccessibilitySnapshotParser
import Foundation
import SwiftUI
import TestHostSupport
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

    @Test func reopeningCanExportBeforeTheCanceledReadReturns() async throws {
        let store = try TestStore()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        let gate = TestStore.OperationGate()
        await store.gateNextExportRead(with: gate)
        let first = BackupModel(services: services)
        let dismissed = Task { await first.exportBackup() }
        await gate.waitUntilReached()
        dismissed.cancel()

        let reopened = BackupModel(services: services)
        var retryFinished = false
        let retry = Task {
            let url = await reopened.exportBackup()
            retryFinished = true
            return url
        }
        do {
            try await waitForAsync { retryFinished }
        } catch {
            retry.cancel()
            await gate.release()
            _ = await dismissed.value
            _ = await retry.value
            await services.backup.discardExport()
            throw error
        }
        await gate.release()
        let url = try #require(await retry.value)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(await dismissed.value == nil)
        #expect(first.backupState == .idle)
        #expect(first.backupError == nil)
        _ = try BackupService().readArchive(at: url)
        await services.backup.discardExport()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func leavingDataAllowsExportAfterReopening() async throws {
        let store = try TestStore()
        let services = WhereServices(store: store, locationSource: ScriptedLocationSource())
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let session = WhereSession(services: services, preferences: preferences)
        let report = YearReportModel(services: services, preferences: preferences)
        let navigation = SettingsView.Navigation()
        let gate = TestStore.OperationGate()
        await store.gateNextExportRead(with: gate)

        let root = SettingsView(
            report: report,
            navigation: navigation,
            initialRoute: SettingsRoute(.data),
        )
        .environment(session)
        .environment(PreviewSupport.loadedModel())
        .whereBroadwayRoot()

        do {
            try await show(UIHostingController(rootView: root)) { controller in
                try await activateExport(in: controller.view)
                await gate.waitUntilReached()
                navigation.selectedRoute = SettingsRoute(.alerts)
                let reminder = AlertsSettingsView.Item.dailyReminder.title
                try await waitForAsync {
                    HostedAccessibility.objects(in: controller.view)
                        .contains { $0.accessibilityLabel == reminder }
                }
                #expect(controller.presentedViewController == nil)
                await gate.release()

                navigation.selectedRoute = SettingsRoute(.data)
                try await activateExport(in: controller.view)
                try await waitForAsync {
                    guard let sheet = controller.presentedViewController else { return false }
                    return sheet.viewIfLoaded?.window != nil && !sheet.isBeingPresented
                }
                await withCheckedContinuation { (dismissed: CheckedContinuation<Void, Never>) in
                    controller.dismiss(animated: false) { dismissed.resume() }
                }
                await services.backup.discardExport()
            }
        } catch {
            await gate.release()
            await services.backup.discardExport()
            throw error
        }
    }

    private func activateExport(in view: UIView) async throws {
        let title = DataSettingsView.Item.exportBackup.title
        try await waitForAsync {
            HostedAccessibility.objects(in: view).contains { $0.accessibilityLabel == title }
        }
        let export = try #require(HostedAccessibility.objects(in: view).first {
            $0.accessibilityLabel == title
        })
        if let control = export as? UIControl { control.sendActions(for: .touchUpInside) }
        else { try #require(export.accessibilityActivate()) }
    }
}

private struct CleanupFailure: Error {}
