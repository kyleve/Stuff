import Foundation
import LifecycleKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func compatibilityRetryResumesThePendingOnboardingGate() async throws {
        let store = try TestStore()
        await store.failCompatibilityVerification(true)
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let bootstrap = ScriptedBootstrap(services: services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
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
        flow.selection.toggle(.newYork)
        flow.finish(using: model)
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .verificationFailed = model.compatibility.state { return true }
            return false
        }
        flow.didDisappear(compatibilityBlocked: true)
        #expect(runner.phase.gateHandle === gate)
        #expect(bootstrap.makeServicesCount == 0)
        #expect(!model.hasOnboarded)
        #expect(flow.isFinishing)

        await store.failCompatibilityVerification(false)
        #expect(await model.refreshCompatibility())
        try await CompatibilityPresentationTestSupport.waitUntil { runner.phase.isReady }
        await launch.value

        #expect(model.hasOnboarded)
        #expect(bootstrap.makeServicesCount == 1)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == false)
        #expect(try await store.primaryRegions().map(\.region) == [.newYork])
        try await services.recording.retireForRejoin()
        await services.ingestor.pause()
    }

    @Test(arguments: [BackupCoordinator.ImportStrategy.merge, .replace])
    func compatibilityRetryRetainsAndImportsTheSelectedArchive(
        strategy: BackupCoordinator.ImportStrategy,
    ) async throws {
        let store = try TestStore()
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let archiveURL = try await services.backup.exportBackup()
        defer {
            do { try FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
            catch { Issue.record(error) }
        }
        await store.failCompatibilityVerification(true)
        let bootstrap = ScriptedBootstrap(services: services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
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
        flow.finish(using: model)
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .verificationFailed = model.compatibility.state { return true }
            return false
        }
        flow.didDisappear(compatibilityBlocked: true)
        #expect(flow.restoreSelection.readyImport?.url == archiveURL)
        #expect(flow.restoreSelection.readyImport?.strategy == strategy)
        #expect(runner.phase.gateHandle === gate)
        #expect(bootstrap.makeServicesCount == 0)

        await store.failCompatibilityVerification(false)
        #expect(await model.refreshCompatibility())
        try await CompatibilityPresentationTestSupport.waitUntil { runner.phase.isReady }
        await launch.value

        #expect(flow.restoreSelection.committedSummary != nil)
        #expect(flow.restoreSelection.readyImport == nil)
        #expect(model.hasOnboarded)
        #expect(bootstrap.makeServicesCount == 1)
        try await services.recording.retireForRejoin()
        await services.ingestor.pause()
    }

    @Test func waitingPreservesTheSelectedArchiveAndDoesNotAuthorizeIt() {
        let model = makeModel(startsAtRecordingChoice: true)
        let url = URL(fileURLWithPath: "/tmp/compatibility-review.zip")
        model.handleRestoreSelection(.success(url))
        model.chooseRestoreStrategy(.replace)
        model.compatibilityReview = .preview
        model.waitForDeviceUpdates()
        #expect(model.compatibilityReview == nil)
        #expect(model.restoreSelection.readyImport?.url == url)
        #expect(model.restoreSelection.readyImport?.strategy == .replace)
        #expect(!model.isFinishing)
        #expect(model.phase == .location)
    }

    @Test func startsAtTheRequestedPhaseAndUsesTheHardwareRecommendation() {
        let model = makeModel(startsAtRecordingChoice: true)

        #expect(model.phase == .location)
        #expect(model.recordingEnabled)
    }

    @Test func finalIntroPageAdvancesToThemeSelection() {
        let model = makeModel(startsAtRecordingChoice: false)
        model.page = OnboardingPage.all.count - 1

        model.advanceIntro(pageCount: OnboardingPage.all.count)

        #expect(model.phase == .theme)
    }

    @Test func normalThemeSelectionContinuesToRegionSelection() {
        let model = makeModel(startsAtRecordingChoice: false)

        model.continueAfterThemeSelection()

        #expect(model.phase == .pickRegions)
    }

    @Test func restoredThemeSelectionContinuesToRecordingConfirmation() {
        let model = makeModel(startsAtRecordingChoice: false)
        model.handleRestoreSelection(.success(URL(fileURLWithPath: "/tmp/where-theme-test.zip")))
        model.chooseRestoreStrategy(.merge)

        #expect(model.phase == .theme)
        model.continueAfterThemeSelection()

        #expect(model.phase == .location)
    }

    private func makeModel(startsAtRecordingChoice: Bool) -> OnboardingFlowModel {
        OnboardingFlowModel(
            gate: LifecycleGateHandle(
                id: LaunchStepID.onboarding,
                reason: .userForeground,
            ),
            installationContext: .testing,
            startsAtRecordingChoice: startsAtRecordingChoice,
            initialTheme: .standard,
        )
    }
}
