import AccessibilitySnapshotParser
import Foundation
@_spi(Testing) import InstallerKitUI
import LifecycleKit
@_spi(Testing) import PeriscopeCore
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereCompatibilityModelTests {
    @Test func recorderCanObtainPermissionAndPublishBeforeOpeningHistory() async throws {
        let harness = CompatibilityLaunchHarness()
        harness.initialAuthorization = .notDetermined
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 2,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        await model.compatibility.refresh(model: model)
        guard case .blocked(.locationPermissionRequired) = model.compatibility.coordinator.state
        else {
            Issue.record("Recording permission must be obtained before publication")
            return
        }
        #expect(harness.opens == 0)
        try await model.installationLocation.requestPermission()
        await model.compatibility.refresh(model: model)
        #expect(harness.source.permissionRequests == 1)
        #expect(await transport.version.rawValue == 2)
        #expect(harness.opens == 0)
        _ = try await model.resolveScope()
        #expect(harness.opens == 1)
        await model.shutdownForCompatibility()
    }

    @Test func demoCannotPublishOrBypassALockout() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 2)
        let model = model(
            currentVersion: 2,
            context: .testing,
            harness: harness,
            transport: transport,
            now: earlyJanuaryDemoDate,
        )
        await model.compatibility.refresh(model: model)
        let demo = try await model.makeDemoScope()
        #expect(await model.activateDemo(demo))
        _ = model.startSession(scope: demo)
        #expect(await demo.services.ingestor.authorizationStatus() == .always)
        await transport.setVersion(1)
        await model.compatibility.refresh(model: model)
        #expect(await transport.version.rawValue == 1)
        #expect(model.compatibility.isBlocking(model))
        #expect(harness.opens == 0)
        await model.shutdownForCompatibility()
    }

    @Test func blockedManualDemoRemainsARecoverableLockout() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let context = InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: Date(),
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        let model = model(
            currentVersion: 2,
            context: context,
            harness: harness,
            transport: transport,
            now: earlyJanuaryDemoDate,
        )
        await model.compatibility.refresh(model: model)
        #expect(!model.compatibility.isBlocking(model))
        let demo = try await model.makeDemoScope()
        #expect(await model.activateDemo(demo) == false)
        #expect(model.compatibility.isBlocking(model))
        #expect(model.activeScope == nil)
        #expect(harness.opens == 0)
        await transport.setVersion(2)
        await model.compatibility.refresh(model: model)
        #expect(!model.compatibility.isBlocking(model))
    }

    @Test func retirementDiscardsAnOpenBeforeReplacement() async throws {
        let harness = CompatibilityLaunchHarness()
        harness.holdNextOpen = true
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let first = Task { try await model.resolveScope() }
        try await waitForAsync { harness.isOpening }
        let retirement = Task { await model.shutdownForCompatibility() }
        try await waitForAsync {
            if case .retiring = model.startupState { true } else { false }
        }
        #expect(harness.opens == 1)
        harness.releaseOpen()
        await #expect(throws: CancellationError.self) { try await first.value }
        await retirement.value
        if model.activeScope == nil { _ = try await model.resolveScope() }
        #expect(harness.opens == 2)
        #expect(harness.stores.first?.store == nil)
        await model.shutdownForCompatibility()
    }

    @Test(arguments: [true, false])
    func recoveryCannotAdmitAnOpeningFromBeforeInvalidation(accountChanged: Bool) async throws {
        let harness = CompatibilityLaunchHarness()
        harness.holdNextOpen = true
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let opening = Task { try await model.resolveScope() }
        try await waitForAsync { harness.isOpening }
        if accountChanged {
            let domain = try model.compatibility.coordinator.requireAccess().domain
            await transport.changeDomain(domain)
            try await waitForAsync { model.compatibility.coordinator.state.allowsStore == false }
        } else {
            await transport.setRejectsReads(true)
            await model.compatibility.refresh(model: model)
            #expect(model.compatibility.coordinator.state.allowsStore == false)
            await transport.setRejectsReads(false)
        }
        await model.compatibility.refresh(model: model)
        #expect(model.compatibility.coordinator.state.allowsStore)
        harness.releaseOpen()
        await #expect(throws: DataCompatibilityFailure.self) { try await opening.value }
        #expect(model.activeScope == nil)
        #expect(harness.stores.first?.store == nil)
        _ = try await model.resolveScope()
        #expect(harness.opens == 2)
        await model.shutdownForCompatibility()
    }

    @Test func recoveringAccessCannotRevealOrReuseThePreviousScope() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        _ = try await model.resolveScope()
        await transport.changeDomain(.local)
        try await waitForAsync { model.compatibility.coordinator.state.allowsStore == false }
        await model.compatibility.refresh(model: model)
        #expect(model.compatibility.coordinator.state.allowsStore)
        #expect(model.compatibility.isBlocking(model))
        await #expect(throws: DataCompatibilityFailure.self) { try await model.resolveScope() }
        await #expect(throws: DataCompatibilityFailure.self) {
            try await model.discoverRecordingRecommendation(for: .testing)
        }
        #expect(harness.opens == 1)
        await model.shutdownForCompatibility()
        _ = try await model.resolveScope()
        #expect(harness.opens == 2)
        #expect(model.compatibility.isBlocking(model) == false)
        await model.shutdownForCompatibility()
    }

    @Test func onboardingOwnedLogoutDoesNotWaitForItself() async throws {
        let harness = CompatibilityLaunchHarness()
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: LaunchCompatibilityTransport(version: 1),
        )
        var finished = false
        model.performOnboarding {
            await model.endSession()
            finished = true
        }
        try await waitForAsync { finished && !model.isCompletingOnboarding }
    }

    @Test func retirementCancelsOnboardingAndPreservesInstallationState() async throws {
        let harness = CompatibilityLaunchHarness()
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: LaunchCompatibilityTransport(version: 1),
        )
        _ = try await model.resolveScope()
        let hold = CompatibilityWorkHold()
        var completionObservedCancellation = false
        model.performOnboarding {
            await hold.wait()
            completionObservedCancellation = Task.isCancelled
        }
        try await waitForAsync { hold.isWaiting }
        var retirementFinished = false
        let retirement = Task {
            await model.shutdownForCompatibility()
            retirementFinished = true
        }
        try await waitForAsync {
            if case .retiring = model.startupState { true } else { false }
        }
        #expect(!retirementFinished)
        #expect(model.isCompletingOnboarding)
        hold.release()
        await retirement.value
        #expect(completionObservedCancellation)
        #expect(!model.isCompletingOnboarding)
        #expect(model.session == nil)
        #expect(model.hasOnboarded)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == true)
    }

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
        now: @escaping @Sendable () -> Date = { Date() },
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
            installationLocation: .init(makeSource: { harness.makeLocationSource() }),
            now: now,
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
        try await waitForAsync { harness.source.stops > 0 }
    }

    @Test func updateLockoutCanBrowseAppUpdatesWithoutOpeningHistory() async throws {
        let harness = CompatibilityLaunchHarness()
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: LaunchCompatibilityTransport(version: 2),
        )
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await model.compatibility.refresh(model: model)
        let host = UIHostingController(rootView: RootView(
            model: model,
            launcher: launcher,
            primaryAppIconName: "AppIcon",
            updates: InstallerPreview.model(.available),
        ))
        try await show(host) { controller in
            controller.view.window?.layer.speed = 1
            let updatesLabel = String(localized: .updatesTitle)
            let doneLabel = String(localized: .commonDone)
            try await activateButton(updatesLabel, in: controller.view)
            let updates = try await presentedSheet(from: controller)

            try await activateButton("Other Builds", in: updates.view)
            let browser = try await presentedSheet(from: updates)
            try await activateButton(doneLabel, in: browser.view)
            try await waitForAsync { updates.presentedViewController == nil }

            try await activateButton(doneLabel, in: updates.view)
            try await waitForAsync {
                controller.presentedViewController == nil
                    && HostedAccessibility.isVisible(updatesLabel, in: controller.view)
            }
            #expect(model.compatibility.isBlocking(model))
            #expect(harness.opens == 0)
        }
    }

    private func activateButton(_ label: String, in view: UIView) async throws {
        try await waitForAsync { HostedAccessibility.isVisible(label, in: view) }
        let button = try #require(HostedAccessibility.objects(in: view)
            .first { $0.accessibilityLabel == label })
        if let control = button as? UIControl {
            control.sendActions(for: .touchUpInside)
        } else {
            try #require(button.accessibilityActivate())
        }
    }

    private func presentedSheet(from controller: UIViewController) async throws
        -> UIViewController
    {
        try await waitForAsync {
            guard let sheet = controller.presentedViewController else { return false }
            return !sheet.isBeingPresented && sheet.transitionCoordinator == nil
        }
        return try #require(controller.presentedViewController)
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
        var reloads = 0
        model.compatibility.onAccessChanged = { reloads += 1 }
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let launch = Task { await launcher.run() }
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        #expect(harness.opens == 0)
        #expect(reloads == 1, "Initial blocked evidence invalidates an existing widget timeline")
        await transport.setVersion(2)
        await model.compatibility.refresh(model: model)
        await launch.value
        #expect(launcher.phase.isReady)
        #expect(harness.opens == 1)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == false)
        await model.compatibility.refresh(model: model)
        #expect(reloads == 2, "Recovery reloads once; repeated allowed decisions do not")
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
        var reloads = 0
        model.compatibility.onAccessChanged = { reloads += 1 }
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        await launcher.run()
        #expect(model.session?.isTracking == true)
        #expect(reloads == 1)
        weak var oldSession = model.session
        let storeReference = try #require(harness.stores.first)
        var blocked = false
        model.compatibility.onBlocked = { _ in blocked = true }
        await transport.setVersion(2)
        await model.compatibility.refresh(model: model)
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        #expect(blocked)
        await model.compatibility.refresh(model: model)
        #expect(reloads == 2, "Withdrawal reloads once; repeated blocks do not")
        #expect(model.session == nil)
        #expect(model.hasOnboarded)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == true)
        try await waitForAsync { oldSession == nil && storeReference.store == nil }
        #expect(harness.opens == 1)
        launcher.phase.gateHandle?.fail(CancellationError())
    }

    /// CompatibilityLockout.BlockedScopeHasRetirement: recovery still owns the previous
    /// teardown task when a detached launch step has not returned.
    @Test func lockoutDuringRecoveryRetiresTheReplacementScope() async throws {
        let harness = CompatibilityLaunchHarness()
        let transport = LaunchCompatibilityTransport(version: 1)
        let model = model(
            currentVersion: 1,
            context: .testing,
            harness: harness,
            transport: transport,
        )
        let hold = CompatibilityRecoveryHold()
        let launcher = LifecycleRunner(
            reason: .userForeground,
            plan: WhereLaunch.plan(for: model).detached { hold },
        )
        model.compatibility.bind(model: model, launcher: launcher)
        defer {
            hold.release()
            launcher.phase.gateHandle?.fail(CancellationError())
        }
        await launcher.run()
        await transport.setRejectsReads(true)
        await model.compatibility.refresh(model: model)
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }

        await transport.setRejectsReads(false)
        await model.compatibility.refresh(model: model)
        try await waitForAsync { hold.isWaiting && launcher.phase.isReady }
        #expect(harness.opens == 2)
        weak var recoveredSession = model.session
        let recoveredStore = try #require(harness.stores.last)
        #expect(await model.session?.services.ingestor.isActive == true)

        await transport.setRejectsReads(true)
        await model.compatibility.refresh(model: model)
        #expect(model.compatibility.isBlocking(model))
        try await waitForAsync { !launcher.phase.isReady }
        // GPS stops before teardown joins the held, cancellation-insensitive launch work.
        #expect(hold.isWaiting)
        #expect(await model.session?.services.ingestor.isActive == false)
        hold.release()
        try await waitForAsync { launcher.phase.isAwaitingGate(LaunchStepID.compatibility) }
        try await waitForAsync { recoveredSession == nil && recoveredStore.store == nil }
        #expect(model.session == nil)
        #expect(harness.opens == 2)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == true)
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
