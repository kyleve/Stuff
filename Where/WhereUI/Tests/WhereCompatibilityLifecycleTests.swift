import Foundation
import LifecycleKit
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereCompatibilityLifecycleTests {
    @Test func unsupportedGateWithholdsServicesAndWithdrawsPreviousOutput() async throws {
        let fixture = try CompatibilityLaunchFixture()
        await fixture.transport.setResult(.success(2))
        let model = fixture.makeModel()
        let gate = DataCompatibilityGate(model: model)
        #expect(gate.modes == .all)
        #expect(await gate.isNeeded(.activeScope))
        #expect(fixture.assemblyCount == 0)
        #expect(fixture.withdrawalCount == 1)
        #expect(model.session == nil)
        #expect(!model.isDataCompatible)
        #expect(try fixture.installation.resolve().automaticRecordingEnabled == true)
    }

    @Test func successfulRetryReopensAHeadlessLaunch() async throws {
        let fixture = try CompatibilityLaunchFixture()
        await fixture.transport.setResult(.failure(CompatibilityLaunchTransport.Offline()))
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let drive = Task { await runner.run() }
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility)
        }
        #expect(fixture.assemblyCount == 0)
        await fixture.transport.setResult(.success(0))
        await model.refreshDataCompatibilityIfNeeded()
        try await CompatibilityLaunchFixture
            .waitUntil { model.session != nil && model.isDataCompatible }
        #expect(fixture.assemblyCount == 1)
        await drive.value
    }

    @Test func backgroundRefreshDoesNotOpenDataBeforeSetupRequestsIt() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        await model.refreshDataCompatibilityIfNeeded()
        #expect(await fixture.transport.verificationCount == 0)
        #expect(fixture.assemblyCount == 0)
        #expect(!model.compatibility.hasChecked)
    }

    @Test func onboardingDiscoveryFailureReleasesTheHandoffWithoutAScope() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        model.preferences.hasOnboarded = false
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        var blocked: (any Error)?
        model.onDataCompatibilityBlocked = { blocked = $0 }
        let drive = Task { await runner.run() }
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.onboarding)
        }
        await fixture.transport.setResult(.success(2))
        await model.compatibility.refresh()
        try await CompatibilityLaunchFixture.waitUntil { blocked != nil }
        #expect(model.activeScope == nil)
        #expect((blocked as? DataCompatibilityError) == .updateRequired(requiredMajor: 2))
        #expect(runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.onboarding))
        // This test does not finish setup. Release its owned drive through the public gate.
        runner.phase.gateHandle?.fail(CompatibilityLaunchTransport.Offline())
        await drive.value
    }

    @Test func foregroundPromotionDoesNotWaitForInitialVerification() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let hold = CompatibilityLaunchSuspension()
        await fixture.transport.holdVerification(hold)
        let headless = Task { await runner.run() }
        defer { hold.resume() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        let foreground = Task {
            await WhereCompatibilityLifecycle.enterForeground(runner: runner, model: model)
        }
        try await CompatibilityLaunchFixture.waitUntil { runner.reason == .userForeground }
        #expect(model.session == nil)
        #expect(model.compatibility.isChecking)
        hold.resume()
        await headless.value
        await foreground.value
        #expect(runner.phase.isReady)
        #expect(model.isDataCompatible)
    }

    @Test func revocationRetiresReadySessionAndPreservesConsent() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        await runner.run()
        let old = try #require(model.activeScope?.services)
        let oldSession = try #require(model.session?.id)
        await fixture.transport.setResult(.failure(CompatibilityLaunchTransport.Offline()))
        fixture.coordinator.invalidateAccount()
        #expect(!model.isDataCompatible)
        #expect(old.isDataAccessRevoked)
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility)
        }
        #expect(model.session == nil)
        #expect(try fixture.installation.resolve().automaticRecordingEnabled == true)
        await fixture.transport.setResult(.success(0))
        await model.compatibility.refresh()
        try await CompatibilityLaunchFixture
            .waitUntil { model.session != nil && model.isDataCompatible }
        #expect(model.session?.id != oldSession)
        #expect(fixture.services?.dataAccessID != old.dataAccessID)
        #expect(throws: (any Error).self) { try old.validateDataAccess() }
    }

    @Test func concurrentScopeRequestsShareOneServiceAssembly() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        async let first = model.resolveScope()
        async let second = model.resolveScope()
        let scopes = try await (first, second)
        #expect(scopes.0 === scopes.1)
        #expect(fixture.assemblyCount == 1)
    }

    @Test func interruptedImportWaitsForVerificationThenRecoversInTheSameLaunch() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let details = try BackupCoordinator.ImportRecoveryDetails(
            transactionID: UUID(),
            installationID: fixture.installation.resolve().currentDevice.id,
            strategy: .merge,
            summary: .init(
                sampleCount: 0,
                evidenceCount: 0,
                manualDayCount: 0,
                dismissedIssueCount: 0,
                trackedRegionCount: 0,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )
        try fixture.installation.setBackupImportRecovery(.committed(
            details,
            cleanupCompleted: true,
            onboardingAcknowledged: false,
        ))
        await fixture.transport.setResult(.failure(CompatibilityLaunchTransport.Offline()))
        let model = fixture.makeModel()
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined)
        let drive = Task { await runner.run() }
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.gateHandle?.id == AnyHashable(LaunchStepID.compatibility)
        }
        #expect(fixture.installation.backupImportRecovery != nil)
        #expect(model.activeScope == nil)
        await fixture.transport.setResult(.success(0))
        await model.refreshDataCompatibilityIfNeeded()
        try await CompatibilityLaunchFixture.waitUntil { runner.phase.isReady }
        await drive.value
        #expect(fixture.installation.backupImportRecovery == nil)
        #expect(model.takeInterruptedOnboardingImportError() == nil)
        #expect(model.isDataCompatible)
    }

    @Test func foregroundPromotionCannotCancelRequiredScopeRetirement() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        let hold = CompatibilityLaunchSuspension()
        var handoffs = 0
        let runner = WhereLaunch.makeLauncher(model: model, reason: .undetermined) { _ in
            handoffs += 1
            if handoffs == 1 { await hold.suspend() }
        }
        let headless = Task { await runner.run() }
        defer { hold.resume() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        let previous = try #require(model.activeScope?.services)
        fixture.coordinator.invalidateAccount()
        try await CompatibilityLaunchFixture.waitUntil {
            if case .launching = runner.phase { true } else { false }
        }
        await model.refreshDataCompatibilityIfNeeded()
        let foreground = Task { await runner.enterForeground() }
        try await CompatibilityLaunchFixture.waitUntil { runner.reason == .userForeground }
        hold.resume()
        try await CompatibilityLaunchFixture.waitUntil {
            runner.phase.isReady && model.isDataCompatible
        }
        await headless.value
        await foreground.value
        #expect(previous.isDataAccessRevoked)
        #expect(model.activeScope?.services.dataAccessID != previous.dataAccessID)
        #expect(fixture.assemblyCount == 2)
    }
}
