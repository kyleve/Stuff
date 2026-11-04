import Foundation
@testable import LifecycleKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct OnboardingFlowModelTests {
    @Test func compatibilityRevocationDuringSetupKeepsTheGateAndDraftRetryable() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let hold = CompatibilityLaunchSuspension()
        fixture.makeLocationSource = { BootstrapHeldAuthorizationSource(hold: hold) }
        let model = fixture.makeModel()
        let gate = LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground)
        let flow = try OnboardingFlowModel(
            gate: gate,
            installationContext: fixture.installation.resolve(),
            startsAtRecordingChoice: true,
            initialTheme: .alternate,
            preferences: model.preferences,
        )
        flow.reminders.issueAlertsEnabled = false
        let finishing = Task { await flow.finish(using: model) }
        defer { hold.resume() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        fixture.coordinator.invalidateAccount()
        await model.suspendForCompatibility()
        hold.resume()
        await finishing.value
        #expect(!flow.isFinishing)
        #expect(flow.phase == .location)
        #expect(flow.theme == .alternate)
        #expect(!flow.reminders.issueAlertsEnabled)
        await model.compatibility.refresh()
        await flow.finish(using: model)
        try await gate.waitForResolution()
        #expect(model.isDataCompatible)
        #expect(fixture.assemblyCount == 2)
    }

    @Test func newerAdmissionRetriesObsoleteAssemblyBeforeOnboardingHasAScope() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let hold = CompatibilityLaunchSuspension()
        fixture.beforeAssembly = { await hold.suspend() }
        let model = fixture.makeModel()
        let gate = LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground)
        let flow = try OnboardingFlowModel(
            gate: gate,
            installationContext: fixture.installation.resolve(),
            startsAtRecordingChoice: true,
            initialTheme: .alternate,
            preferences: model.preferences,
        )
        let finishing = Task { await flow.finish(using: model) }
        defer { hold.resume() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        #expect(model.activeScope == nil)
        let previous = try #require(fixture.coordinator.access)
        fixture.coordinator.invalidateAccount()
        await model.compatibility.refresh()
        #expect(model.isDataCompatible)
        #expect(fixture.coordinator.access?.id != previous.id)
        hold.resume()
        await finishing.value
        try await gate.waitForResolution()
        #expect(model.isDataCompatible)
        #expect(fixture.assemblyCount == 1)
        #expect(!flow.isFinishing)
    }

    @Test func aDurableImportReceiptPreventsRepeatingARetainedRestoreDraft() async throws {
        let fixture = try CompatibilityLaunchFixture()
        let model = fixture.makeModel()
        let gate = LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground)
        let flow = try OnboardingFlowModel(
            gate: gate,
            installationContext: fixture.installation.resolve(),
            startsAtRecordingChoice: true,
            initialTheme: .standard,
            preferences: model.preferences,
        )
        // The previous save committed, but revocation hid its successful return from the UI.
        // Its archive is deliberately unavailable: retry must rely on the receipt, never read it.
        flow.restoreSelection.select(
            url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            hasScopedAccess: false,
        )
        flow.restoreSelection.choose(.replace)
        let details = try BackupCoordinator.ImportRecoveryDetails(
            transactionID: UUID(),
            installationID: fixture.installation.resolve().currentDevice.id,
            strategy: .replace,
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
        try fixture.installation.setBackupImportRecovery(.prepared(details))
        try await fixture.store.perform {
            try await fixture.store.addBackupImportReceipt(
                id: details.transactionID,
                installationID: details.installationID,
            )
        }
        let generation = try await fixture.store.dataGeneration().id
        await flow.finish(using: model)
        try await gate.waitForResolution()
        #expect(flow.restoreSelection.committedSummary == details.summary)
        #expect(flow.restoreSelection.readyImport == nil)
        #expect(fixture.installation.backupImportRecovery == nil)
        #expect(try await fixture.store.dataGeneration().id == generation)
        #expect(model.isDataCompatible)
    }

    @Test func failedSetupDoesNotLetARestoredOnboardingFlagSkipTheNextGate() async throws {
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let contextStore =
            InMemoryInstallationRecordingContextStore(context: InstallationRecordingContext(
                currentDevice: InstallationRecordingContext.testing.currentDevice,
                registeredAt: InstallationRecordingContext.testing.registeredAt,
                recordingChoice: .unconfirmed,
                isRejoining: false,
            ))
        func makeAppModel() -> WhereModel {
            WhereModel(
                preferences: preferences,
                installationContextStore: contextStore,
                makeBootstrap: { _ in FailingBootstrap() },
                logSystem: .isolated(),
            )
        }
        let model = makeAppModel()
        let flow = try OnboardingFlowModel(
            gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
            installationContext: contextStore.resolve(),
            startsAtRecordingChoice: true,
            initialTheme: .standard,
            preferences: preferences,
        )
        flow.reminders.issueAlertsEnabled = false
        await flow.finish(using: model)
        #expect(try model.hasConfirmedRecordingChoice)
        #expect(!preferences.issueAlertsEnabled)
        #expect(try !contextStore.resolve().hasCompletedSetup)
        let relaunched = makeAppModel()
        #expect(try await OnboardingGate(model: relaunched)
            .isNeeded(.installation(contextStore.resolve())))
    }

    @Test func renewedConsentFinishesPendingImportCleanupBeforeStartingCapture() async throws {
        let contextStore =
            InMemoryInstallationRecordingContextStore(context: InstallationRecordingContext(
                currentDevice: InstallationRecordingContext.testing.currentDevice,
                registeredAt: InstallationRecordingContext.testing.registeredAt,
                recordingChoice: .unconfirmed,
                isRejoining: false,
            ))
        contextStore.setBackupImportRecovery(.committed(
            BackupCoordinator.ImportRecoveryDetails(
                transactionID: UUID(),
                installationID: InstallationRecordingContext.testing.currentDevice.id,
                strategy: .replace,
                summary: BackupCoordinator.ImportSummary(
                    sampleCount: 0,
                    evidenceCount: 0,
                    manualDayCount: 0,
                    dismissedIssueCount: 0,
                    trackedRegionCount: 0,
                    recordingDeviceCount: 0,
                    recordingDeviceRemovalCount: 0,
                ),
            ),
            cleanupCompleted: false,
            onboardingAcknowledged: false,
        ))
        let outbox = OnboardingSetupOutbox()
        let fixture = try OnboardingSetupFixture(installationStore: contextStore, outbox: outbox)
        let flow = try fixture.flow()
        let finishing = Task { await flow.finish(using: fixture.model) }
        defer { finishing.cancel(); Task { await outbox.release() } }
        try await outbox.waitUntilClearing()
        #expect(try await fixture.store.recordingDeviceProfiles().isEmpty)
        #expect(await fixture.model.activeScope?.services.ingestor.isActive == false)
        await outbox.release()
        await finishing.value
        #expect(contextStore.backupImportRecovery == nil)
        #expect(await fixture.model.activeScope?.services.ingestor.isActive == true)
    }

    @Test func renewedConsentReturnsToRestoreWhenAnOldPreparedImportNeverCommitted() async throws {
        let oldIdentity = InstallationRecordingContext.testing.currentDevice.id
        let contextStore =
            InMemoryInstallationRecordingContextStore(context: InstallationRecordingContext(
                currentDevice: CurrentRecordingDevice(
                    id: .init(rawValue: UUID()),
                    systemName: "iPhone",
                    kind: .phone,
                ),
                registeredAt: Date(),
                recordingChoice: .unconfirmed,
                isRejoining: false,
            ))
        contextStore.setBackupImportRecovery(.prepared(BackupCoordinator.ImportRecoveryDetails(
            transactionID: UUID(),
            installationID: oldIdentity,
            strategy: .replace,
            summary: BackupCoordinator.ImportSummary(
                sampleCount: 1,
                evidenceCount: 0,
                manualDayCount: 0,
                dismissedIssueCount: 0,
                trackedRegionCount: 0,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )))
        let fixture = try OnboardingSetupFixture(installationStore: contextStore)
        let flow = try fixture.flow()
        await flow.finish(using: fixture.model)
        #expect(flow.phase == .intro)
        #expect(!flow.isFinishing)
        #expect(!fixture.model.hasOnboarded)
        #expect(fixture.model.activeScope == nil)
        #expect(contextStore.backupImportRecovery == nil)
        #expect(try !contextStore.resolve().hasCompletedSetup)
        #expect(try await fixture.store.recordingDeviceProfiles().isEmpty)
    }

    @Test(arguments: [false, true])
    func replacementRemovesTheOldDeviceOnlyWhenExplicitlySelected(
        removeOldDevice: Bool,
    ) async throws {
        let fixture =
            try OnboardingSetupFixture(
                installationStore: InMemoryInstallationRecordingContextStore(context: .testing),
            )
        let otherID = RecordingDeviceID(rawValue: UUID())
        try await fixture.addDevice(otherID)
        let flow = try fixture.flow()
        flow.deviceSetup.replacementDeviceID = otherID
        flow.deviceSetup.removesOldDevice = removeOldDevice
        flow.recordingEnabled = false
        await flow.finish(using: fixture.model)
        #expect(fixture.model.hasOnboarded)
        let removals = try await fixture.store.recordingDeviceRemovals()
        #expect(removals.contains { $0.deviceID == otherID } == removeOldDevice)
        #expect(try fixture.installationStore.resolve().currentDevice
            .id == InstallationRecordingContext.testing.currentDevice.id)
        #expect(fixture.preferences.remindersEnabled && fixture.preferences.issueAlertsEnabled)
        #expect(await fixture.model.activeScope?.services.ingestor.isActive == false)
    }

    @Test func reinstalledRemovedIdentityFinishesIntoTheExplicitRejoinScreen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "OnboardingRemovedIdentity.\(UUID().uuidString)")
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                do { try FileManager.default.removeItem(at: directory) }
                catch { Issue.record(error) }
            }
        }
        let identityStore = ScriptedRecordingIdentityStore()
        let originalID = InstallationRecordingContext.testing.currentDevice.id
        identityStore.identity = InstallationRecordingIdentity(
            deviceID: originalID,
            registeredAt: InstallationRecordingContext.testing.registeredAt,
            creation: .initial,
        )
        let contextStore = FileInstallationRecordingContextStore(
            identityStore: identityStore,
            fileURL: directory.appending(path: "context.json"),
            fileManager: .default,
            systemName: "iPhone",
            kind: .phone,
            makeUUID: { UUID() },
            now: { Date() },
        )
        #expect(try contextStore.resolve().automaticRecordingEnabled == nil)
        let fixture = try OnboardingSetupFixture(installationStore: contextStore)
        try await fixture.addDevice(originalID)
        try await fixture.store.perform {
            try await fixture.store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: .init(rawValue: UUID()),
                deviceID: originalID,
                removedAt: Date(timeIntervalSinceReferenceDate: 100),
                removedByDeviceID: .init(rawValue: UUID()),
            ))
        }
        let flow = try fixture.flow()
        await flow.finish(using: fixture.model)
        #expect(fixture.model.hasOnboarded)
        let launcher = WhereLaunch.makeLauncher(model: fixture.model, reason: .userForeground)
        await launcher.run()
        #expect(launcher.phase.isReady)
        let session = try #require(fixture.model.session)
        #expect(session.isCurrentDeviceRemoved)
        #expect(!session.isTracking)
        #expect(identityStore.replacementCount == 0)
        try await session.prepareDeviceRejoin()
        try await fixture.model.rejoinInstallation()
        #expect(identityStore.replacementCount == 1)
        #expect(try contextStore.resolve().currentDevice.id != originalID)
        #expect(try contextStore.resolve().automaticRecordingEnabled == nil)
        #expect(try await fixture.store.recordingDeviceRemovals()
            .contains { $0.deviceID == originalID })
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
            preferences: makePreferences(),
        )
    }
}
