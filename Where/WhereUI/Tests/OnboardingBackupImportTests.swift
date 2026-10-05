import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingBackupImportTests {
    @Test(
        arguments: [BackupCoordinator.ImportStrategy.merge, .replace],
        TestStore.ImportCompatibilityInterruption.allCases,
    )
    func blockedImportResumesFromItsReceiptWithoutReplayingACommit(
        strategy: BackupCoordinator.ImportStrategy,
        interruption: TestStore.ImportCompatibilityInterruption,
    ) async throws {
        let store = try TestStore()
        let installationStore = makeInstallationRecordingContextStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            importRecoveryPersistence: installationStore,
        )
        let sourceStore = try SwiftDataStore.inMemory()
        let sample = LocationSample(
            timestamp: Date(timeIntervalSince1970: 1000),
            coordinate: .init(latitude: 40, longitude: -74),
            horizontalAccuracy: 5,
            source: .manual,
        )
        try await sourceStore.perform { try await sourceStore.add(sample: sample) }
        let sourceServices = CompatibilityPresentationTestSupport.services(
            store: sourceStore,
            source: ScriptedLocationSource(),
        )
        let archiveURL = try await sourceServices.backup.exportBackup()
        defer {
            do { try FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
            catch { Issue.record(error) }
        }
        let bootstrap = ScriptedBootstrap(services: services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: installationStore,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let launch = Task { await runner.run() }
        defer { launch.cancel(); model.compatibility.detach() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            runner.phase.gateHandle != nil
        }
        let gate = try #require(runner.phase.gateHandle)
        let flow = OnboardingFlowModel(
            gate: gate,
            installationContext: model.installationRecordingContext,
            startsAtRecordingChoice: true,
            initialTheme: .standard,
        )
        flow.recordingEnabled = false
        flow.handleRestoreSelection(.success(archiveURL))
        flow.chooseRestoreStrategy(strategy)
        await store.interruptNextImport(interruption)
        flow.finish(using: model)
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .verificationFailed = model.compatibility.state { return true }
            return false
        }
        flow.didDisappear(compatibilityBlocked: true)
        #expect(runner.phase.gateHandle === gate)
        #expect(flow.isFinishing)
        #expect(flow.restoreSelection.readyImport?.url == archiveURL)
        #expect(installationStore.backupImportRecovery != nil)
        #expect(await store.importWriteAttempts == 1)
        #expect(!model.hasOnboarded)

        await store.failCompatibilityVerification(false)
        #expect(await model.refreshCompatibility())
        try await CompatibilityPresentationTestSupport.waitUntil { runner.phase.isReady }
        await launch.value

        #expect(model.hasOnboarded)
        #expect(flow.restoreSelection.committedSummary != nil)
        #expect(installationStore.backupImportRecovery == nil)
        #expect(installationStore.onboardingImportCompletion != nil)
        #expect(await store.importWriteAttempts == (interruption == .beforeCommit ? 2 : 1))
        #expect(try await store.allSamples().map(\.id) == [sample.id])
        #expect(try await services.backup.importRecoveryState() == .ready)
        try await services.recording.retireForRejoin()
        await services.ingestor.pause()
    }
}
