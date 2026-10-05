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

    @Test(arguments: [BackupCoordinator.ImportStrategy.merge, .replace], [false, true])
    func importUsesLiveAvailabilityAndRechecksTheDisplayedApproval(
        strategy: BackupCoordinator.ImportStrategy,
        continueAnyway: Bool,
    ) async throws {
        let world = try await DataFeatureAvailabilityTestSupport.makeWorld()
        let archiveURL = try await DataFeatureAvailabilityTestSupport.exportFutureBackup()
        defer {
            do { try FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
            catch { Issue.record(error) }
        }
        let bootstrap = ScriptedBootstrap(services: world.services)
        let model = WhereModel(
            preferences: makePreferences(),
            installationContextStore: makeInstallationRecordingContextStore(),
            makeBootstrap: { _ in bootstrap },
            logSystem: .isolated(),
        )
        let runner = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        let launch = Task { await runner.run() }
        var observation: Task<Void, Never>?
        defer {
            observation?.cancel()
            launch.cancel()
            model.compatibility.detach()
        }
        try await CompatibilityPresentationTestSupport.waitUntil {
            runner.phase.gateHandle != nil
        }
        let flow = try OnboardingFlowModel(
            gate: #require(runner.phase.gateHandle),
            installationContext: model.installationRecordingContext,
            startsAtRecordingChoice: true,
            initialTheme: .standard,
        )
        flow.recordingEnabled = false
        flow.handleRestoreSelection(.success(archiveURL))
        flow.chooseRestoreStrategy(strategy)
        flow.finish(using: model)
        try await CompatibilityPresentationTestSupport.waitUntil {
            flow.compatibilityAvailability != nil
        }
        flow.waitForDeviceUpdates()
        #expect(flow.restoreSelection.readyImport?.url == archiveURL)
        #expect(flow.restoreSelection.readyImport?.strategy == strategy)
        #expect(try await world.store.dataCompatibility().requiredVersion == .initial)

        flow.finish(using: model)
        try await CompatibilityPresentationTestSupport.waitUntil {
            flow.compatibilityAvailability != nil
        }
        let availability = try #require(flow.compatibilityAvailability)
        observation = Task { await availability.observe() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .needsDeviceReview = availability.state { return true }
            return false
        }
        guard case let .needsDeviceReview(displayedReview) = availability.state else {
            Issue.record("Import must first show the unknown device.")
            return
        }
        if continueAnyway {
            try await DataFeatureAvailabilityTestSupport.register(
                RecordingDeviceID(rawValue: UUID()),
                in: world.store,
            )
            try await CompatibilityPresentationTestSupport.waitUntil {
                if case let .needsDeviceReview(review) = availability.state {
                    return review.affectedDevices.count == 2
                }
                return false
            }
            observation?.cancel()
            // The tapped button carries its displayed review, even if observation has moved on.
            flow.continueAfterCompatibilityReview(
                using: model,
                approval: .continueAnyway(displayedReview),
            )
            try await CompatibilityPresentationTestSupport.waitUntil {
                flow.compatibilityAvailability != nil
            }
            #expect(flow.restoreSelection.committedSummary == nil)
            #expect(try await world.store.dataCompatibility().requiredVersion == .initial)
            let freshAvailability = try #require(flow.compatibilityAvailability)
            #expect(freshAvailability !== availability)
            await freshAvailability.refresh()
            guard case let .needsDeviceReview(freshReview) = freshAvailability.state else {
                Issue.record("A stale approval must produce a fresh warning.")
                return
            }
            #expect(freshReview.affectedDevices.count == 2)
            flow.continueAfterCompatibilityReview(
                using: model,
                approval: .continueAnyway(freshReview),
            )
        } else {
            try await world.store.publishDataCapability(
                for: world.otherDeviceID,
                at: DataFeatureAvailabilityTestSupport.now,
            )
            try await CompatibilityPresentationTestSupport.waitUntil {
                if case .available = availability.state { return true }
                return false
            }
            observation?.cancel()
            flow.continueAfterCompatibilityReview(using: model, approval: .readyDevicesOnly)
        }
        // SwiftUI may write the dismissed binding after Continue has started the import.
        flow.isShowingCompatibilityReview = false
        #expect(flow.isFinishing)
        try await CompatibilityPresentationTestSupport.waitUntil { runner.phase.isReady }
        await launch.value
        #expect(flow.restoreSelection.committedSummary != nil)
        #expect(try await world.store.dataCompatibility()
            .requiredVersion == DataFeatureAvailabilityTestSupport.version)
        #expect(bootstrap.makeServicesCount == 1)
        #expect(model.installationRecordingContext.automaticRecordingEnabled == false)
        try await world.services.recording.retireForRejoin()
        await world.services.ingestor.pause()
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
