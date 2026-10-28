import Foundation
import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereCompatibilityLifecycleTests {
    @Test func historyChangeInterruptsOnboardingBeforeAnyScopeExists() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let model = makeOnboardingModel(bootstrap)
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let drive = Task { await runner.run() }
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.onboarding) }
        let original = try #require(runner.phase.gateHandle)
        let flow = makeFlow(gate: original, model: model)
        try await requireUpdate(bootstrap)
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.compatibility) }
        await drive.value
        original.complete()
        flow.finish(using: model)
        flow.enterDemoMode(using: model)
        await model.compatibility.refresh()
        #expect(runner.phase.isAwaitingGate(LaunchStepID.compatibility))
        #expect(bootstrap.makeServicesCount == 0)
        #expect(model.activeScope == nil)
        #expect(!model.hasOnboarded)
        #expect(!model.isInDemoMode)
    }

    @Test(arguments: [false, true])
    func interruptedOnboardingDrainsSuspendedWork(afterScopeActivation: Bool) async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let dependency = CompatibilityOperationGate()
        if afterScopeActivation {
            bootstrap.locationSource = CompatibilityGatedLocationSource(authorization: dependency)
        } else {
            bootstrap.serviceAssemblyGate = dependency
        }
        let model = makeOnboardingModel(bootstrap)
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let drive = Task { await runner.run() }
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.onboarding) }
        let original = try #require(runner.phase.gateHandle)
        let flow = makeFlow(gate: original, model: model)
        if !afterScopeActivation {
            flow
                .handleRestoreSelection(
                    .success(URL(fileURLWithPath: "/tmp/interrupted-restore.zip")),
                )
            flow.chooseRestoreStrategy(.merge)
        }
        flow.finish(using: model)
        try await wait { dependency.entered }
        #expect((model.activeScope != nil) == afterScopeActivation)
        let consent = try bootstrap.installation.resolve().recordingChoice
        try await requireUpdate(bootstrap)
        try await wait { dependency.cancelled }
        flow.discardPendingRestore() // The gate's view disappears while work is draining.
        if !afterScopeActivation { #expect(flow.restoreSelection.readyImport != nil) }
        // The replacement drive cannot reach its gate until the old finish task drains.
        #expect(!runner.phase.isAwaitingGate(LaunchStepID.compatibility))
        #expect(!model.hasOnboarded)
        dependency.release()
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.compatibility) }
        await drive.value
        #expect(model.activeScope == nil)
        #expect(!model.hasOnboarded)
        #expect(!flow.isFinishing)
        #expect(flow.restoreSelection.readyImport == nil)
        #expect(bootstrap.makeServicesCount == 1)
        #expect(bootstrap.makeLogStoreCount == (afterScopeActivation ? 1 : 0))
        #expect(try bootstrap.installation.resolve().recordingChoice == consent)
        original.complete()
        flow.finish(using: model)
        await model.compatibility.refresh()
        #expect(runner.phase.isAwaitingGate(LaunchStepID.compatibility))
        #expect(bootstrap.makeServicesCount == 1)
    }

    @Test func compatibilityCanInterruptOnboardingRecoveryBeforeItParks() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let recovery = BackupCoordinator.DurableImportRecovery.committed(
            .init(
                transactionID: UUID(),
                strategy: .merge,
                summary: .init(
                    sampleCount: 1,
                    evidenceCount: 0,
                    manualDayCount: 0,
                    dismissedIssueCount: 0,
                    trackedRegionCount: 0,
                    recordingDeviceCount: 0,
                    recordingDeviceRemovalCount: 0,
                ),
            ),
            cleanupCompleted: true,
            onboardingAcknowledged: false,
        )
        bootstrap.installation.setBackupImportRecovery(recovery)
        let dependency = CompatibilityOperationGate()
        bootstrap.serviceAssemblyGate = dependency
        let model = makeOnboardingModel(bootstrap)
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let drive = Task { await runner.run() }
        try await wait { dependency.entered }
        #expect(runner.phase.isRunning(LaunchStepID.onboarding))
        #expect(model.activeScope == nil)
        try await requireUpdate(bootstrap)
        try await wait { dependency.cancelled }
        dependency.release()
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.compatibility) }
        await drive.value
        #expect(model.activeScope == nil)
        #expect(!model.hasOnboarded)
        #expect(bootstrap.installation.backupImportRecovery == recovery)
        #expect(bootstrap.makeServicesCount == 1)
        #expect(bootstrap.makeLogStoreCount == 0)
    }

    @Test func retryReturnsToFreshOnboardingAndCanBeInterruptedAgain() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let model = makeOnboardingModel(bootstrap)
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let drive = Task { await runner.run() }
        try await wait { runner.phase.isAwaitingGate(LaunchStepID.onboarding) }
        for _ in 0 ..< 2 {
            let oldGate = try #require(runner.phase.gateHandle)
            bootstrap.preparationError = VerificationFailure()
            await model.compatibility.refresh()
            try await wait { runner.phase.isAwaitingGate(LaunchStepID.compatibility) }
            #expect(model.activeScope == nil)
            bootstrap.preparationError = nil
            await model.compatibility.refresh()
            try await wait { runner.phase.isAwaitingGate(LaunchStepID.onboarding) }
            #expect(runner.phase.gateHandle !== oldGate)
            oldGate.complete()
        }
        #expect(bootstrap.makeServicesCount == 0)
        #expect(!model.hasOnboarded)
        let gate = try #require(runner.phase.gateHandle)
        let flow = makeFlow(gate: gate, model: model)
        flow.finish(using: model)
        try await wait { runner.phase.isReady }
        await drive.value
        #expect(model.hasOnboarded)
        #expect(!flow.isFinishing)
        #expect(bootstrap.makeServicesCount == 1)
    }

    @Test func restoredHeadlessLaunchRequiresChoiceBeforeServices() async throws {
        let bootstrap = try CompatibilityBootstrap()
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: bootstrap.installation,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        let drive = Task { await runner.run() }
        defer { drive.cancel() }
        try await wait { runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility) }
        #expect(model.compatibility.state == .recordingChoiceRequired)
        #expect(bootstrap.makeServicesCount == 0)
        #expect(model.activeScope == nil)
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        await model.compatibility.refresh()
        try await wait { runner.phase.isReady }
        await drive.value
        #expect(bootstrap.makeServicesCount == 1)
        #expect(model.activeScope != nil)
    }

    @Test func historyChangeRetiresTheActiveScopeAndPreservesConsent() async throws {
        let bootstrap = try CompatibilityBootstrap()
        _ = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            installationContextStore: bootstrap.installation,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .background(.location))
        await runner.run()
        #expect(runner.phase.isReady)
        let consent = try bootstrap.installation.resolve().recordingChoice
        let oldStore = try #require(bootstrap.lastDomainStore)
        let required = DataCompatibilityVersion(rawValue: 2)
        try await bootstrap.store.perform {
            try await bootstrap.store.addDataCompatibilityRequirement(.init(
                id: UUID(),
                version: required,
            ))
        }
        try await wait {
            model.compatibility.state == .updateRequired(required) && model.activeScope == nil
        }
        #expect(try bootstrap.installation.resolve().recordingChoice == consent)
        #expect(bootstrap.makeServicesCount == 1)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await oldStore.perform {}
        }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw Timeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func makeOnboardingModel(_ bootstrap: CompatibilityBootstrap) -> WhereModel {
        WhereModel(
            preferences: makePreferences(),
            installationContextStore: bootstrap.installation,
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
    }

    private func makeFlow(gate: LifecycleGateHandle, model: WhereModel) -> OnboardingFlowModel {
        OnboardingFlowModel(
            gate: gate,
            installationContext: model.installationRecordingContext,
            startsAtRecordingChoice: true,
            initialTheme: .standard,
        )
    }

    private func requireUpdate(_ bootstrap: CompatibilityBootstrap) async throws {
        try await bootstrap.store.perform {
            try await bootstrap.store.addDataCompatibilityRequirement(.init(
                id: UUID(),
                version: .init(rawValue: 2),
            ))
        }
    }

    private struct VerificationFailure: Error {}
    private struct Timeout: Error {}
}
