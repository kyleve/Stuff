import Foundation
import LifecycleKit
@_spi(Testing) import PeriscopeCore
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereCompatibilityModelTests {
    @Test func foregroundPollDetectsAChangeWithoutAPush() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let clock = CompatibilityPollClock()
        model.compatibility.setPollWait { try await clock.wait() }
        model.compatibility.setForeground(true, model: model)
        defer { model.compatibility.setForeground(false, model: model) }
        try await waitForAsync { clock.waitCount == 1 }
        #expect(model.compatibility.coordinator.state.allowsStore)
        await transport.setVersion(2)
        clock.tick()
        try await waitForAsync { !model.compatibility.coordinator.state.allowsStore }
        #expect(harness.opens == 0)
    }

    @Test func onboardingCompletionHasOneProcessOwnedTask() async throws {
        let harness = CompatibilityLaunchHarness()
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: LaunchCompatibilityTransport(version: 1),
        )
        let clock = CompatibilityPollClock()
        var starts = 0
        model.performOnboarding {
            starts += 1
            do { try await clock.wait() }
            catch { Issue.record(error) }
        }
        try await waitForAsync { clock.waitCount == 1 }
        model.performOnboarding { starts += 1 }
        #expect(starts == 1)
        #expect(model.isCompletingOnboarding)
        clock.tick()
        try await waitForAsync { !model.isCompletingOnboarding }
    }

    private func model(
        currentVersion: Int,
        context: InstallationRecordingContext,
        harness: CompatibilityLaunchHarness,
        transport: LaunchCompatibilityTransport,
    ) -> WhereModel {
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let compatibility = WhereCompatibilityModel(coordinator: DataCompatibilityCoordinator(
            transport: transport,
            receipts: LaunchCompatibilityReceipt(),
            version: .init(rawValue: currentVersion),
        ))
        return WhereModel(
            preferences: preferences,
            installationContextStore: InMemoryInstallationRecordingContextStore(context: context),
            makeBootstrap: { CompatibilityLaunchBootstrap(harness: harness, context: $0) },
            logSystem: .isolated(),
            compatibility: compatibility,
        )
    }

    @Test(arguments: [LifecycleReason.userForeground, .undetermined])
    func blockedLaunchAndDiscoveryNeverOpenHistory(reason: LifecycleReason) async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 2)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let launcher = WhereLaunch.makeLauncher(model: model, reason: reason)
        let launch = Task { await launcher.run() }
        defer { launcher.phase.gateHandle?.fail(CancellationError()); launch.cancel() }
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        #expect(harness.opens == 0)
        await #expect(throws: DataCompatibilityFailure.self) {
            try await model.discoverRecordingRecommendation(for: .testing)
        }
        #expect(harness.discoveries == 0)
        #expect(model.session == nil)
        try await waitForAsync { harness.locationStops > 0 }
    }

    @Test func waitingViewerRecoversWithOneFreshScope() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 2,
            context: InstallationRecordingContext.testing.settingAutomaticRecordingEnabled(
                false,
                at: Date(),
            ),
            harness: harness,
            transport: transport,
        )
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let launch = Task { await launcher.run() }
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        #expect(harness.opens == 0)
        await transport.setVersion(2)
        await model.compatibility.refresh(model: model)
        await launch.value
        #expect(launcher.phase.isReady)
        #expect(harness.opens == 1)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == false)
        await model.session?.shutdown()
    }

    @Test func runningLockoutReleasesStoreAndPreservesConsent() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(model.session?.isTracking == true)
        weak var oldSession = model.session
        let storeReference = try #require(harness.stores.first)
        var blocked = false
        model.compatibility.onBlocked = { _ in blocked = true }
        await transport.setVersion(2)
        await model.compatibility.refresh(model: model)
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        #expect(blocked)
        #expect(model.session == nil)
        #expect(model.hasOnboarded)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == true)
        try await waitForAsync { oldSession == nil && storeReference.store == nil }
        #expect(harness.opens == 1)
        launcher.phase.gateHandle?.fail(CancellationError())
    }

    @Test func initialOffChoiceBecomesVisibleLockoutWithoutOpeningStore() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let unconfirmed = InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        let model = model(
            currentVersion: 2,
            context: unconfirmed,
            harness: harness,
            transport: transport,
        )
        await model.compatibility.refresh(model: model)
        #expect(!model.compatibility.isBlocking(model))
        try model.confirmInitialRecordingChoice(isEnabled: false)
        await model.compatibility.refresh(model: model)
        #expect(model.compatibility.isBlocking(model))
        #expect(harness.opens == 0)
    }
}
