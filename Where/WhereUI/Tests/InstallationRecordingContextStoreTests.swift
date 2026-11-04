import CloudKit
import Foundation
import Testing
import UIKit
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct InstallationRecordingContextStoreTests {
    @Test func sameDeviceReinstallRetainsIdentityAndRequiresConsentAtTheNewTime() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let original = try fixture.makeStore().confirmInitialRecording(isEnabled: true)
        try FileManager.default.removeItem(at: fixture.directory)
        let confirmedAt = Self.registeredAt.addingTimeInterval(30 * 24 * 3600)
        let reinstalled = fixture.makeStore(ids: [], dates: [confirmedAt])
        let proposed = try reinstalled.resolve()
        #expect(proposed.currentDevice.id == original.currentDevice.id)
        #expect(proposed.registeredAt == original.registeredAt)
        #expect(proposed.automaticRecordingEnabled == nil)
        #expect(fixture.fileExists == false)
        let confirmed = try reinstalled.confirmInitialRecording(isEnabled: true)
        #expect(confirmed.recordingEnabledAt == confirmedAt)
        #expect(fixture.identityStore.creationCount == 1)
    }

    @Test func missingKeychainCannotAdoptTheIdentityFromABoundSidecar() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let original = try fixture.makeStore().confirmInitialRecording(isEnabled: true)
        fixture.identityStore.identity = nil
        let replacement = fixture.makeStore(
            ids: [Self.resetDeviceID],
            dates: [Self.resetRegisteredAt, Self.resetRegisteredAt],
        )
        let proposed = try replacement.resolve()
        #expect(proposed.currentDevice.id != original.currentDevice.id)
        #expect(proposed.automaticRecordingEnabled == nil)
        #expect(fixture.identityStore.identity == nil)
        _ = try replacement.confirmInitialRecording(isEnabled: false)
        #expect(fixture.identityStore.identity?.deviceID == proposed.currentDevice.id)
    }

    @Test func identityReplacementKeepsThePreparedImportsOriginalReceiptOwner() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let original = fixture.makeStore()
        let confirmed = try original.confirmInitialRecording(isEnabled: true)
        let details = BackupCoordinator.ImportRecoveryDetails(
            transactionID: UUID(),
            installationID: confirmed.currentDevice.id,
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
        )
        try original.setBackupImportRecovery(.prepared(details))
        // An older local marker had no separate owner. Bind it to its original sidecar before
        // rebinding the sidecar itself to a replacement identity.
        var payload = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.fileURL),
        ) as? [String: Any])
        var recovery = try #require(payload["backupImportRecovery"] as? [String: Any])
        recovery.removeValue(forKey: "installationID")
        payload["backupImportRecovery"] = recovery
        try JSONSerialization.data(withJSONObject: payload).write(to: fixture.fileURL)
        fixture.identityStore.identity = nil
        let replacement = fixture.makeStore(
            ids: [Self.resetDeviceID],
            dates: [Self.resetRegisteredAt, Self.resetRegisteredAt],
        )
        _ = try replacement.confirmInitialRecording(isEnabled: false)
        let relaunched = fixture.makeStore(ids: [], dates: [])
        #expect(try relaunched.resolve().currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(relaunched.backupImportRecovery == .prepared(details))
    }

    @Test func lockedIdentityAllocatesNothingAndRetriesAfterAccessReturns() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let original = try fixture.makeStore().confirmInitialRecording(isEnabled: true)
        fixture.identityStore.failure = .unavailable
        let unavailable = fixture.makeStore(ids: [], dates: [])
        #expect(throws: ScriptedRecordingIdentityStore.Failure.self) { try unavailable.resolve() }
        #expect(throws: ScriptedRecordingIdentityStore.Failure.self) {
            try unavailable.onboardingContext
        }
        #expect(fixture.identityStore.creationCount == 1)
        fixture.identityStore.failure = nil
        #expect(try unavailable.resolve() == original)
        #expect(fixture.identityStore.creationCount == 1)
    }

    @Test func ordinaryUpgradeAdoptsLegacySidecarWithoutChangingConsent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = try store.confirmInitialRecording(isEnabled: true)
        try store.completeSetup()
        let original = try store.resolve()
        var payload = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any])
        payload.removeValue(forKey: "usesKeychainIdentity")
        payload.removeValue(forKey: "hasCompletedSetup")
        try JSONSerialization.data(withJSONObject: payload).write(
            to: fixture.fileURL,
            options: .atomic,
        )
        fixture.identityStore.identity = nil
        #expect(try fixture.makeStore(ids: [], dates: []).resolve() == original)
        #expect(fixture.identityStore.identity?.deviceID == original.currentDevice.id)
        let upgraded = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any])
        #expect(upgraded["usesKeychainIdentity"] as? Bool == true)
    }

    @Test func setupCompletionSurvivesRelaunchSeparatelyFromConsent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = try store.confirmInitialRecording(isEnabled: false)
        let relaunched = fixture.makeStore(ids: [], dates: [])
        #expect(try relaunched.resolve().automaticRecordingEnabled == false)
        #expect(try !relaunched.resolve().hasCompletedSetup)
        try relaunched.completeSetup()
        #expect(try fixture.makeStore(ids: [], dates: []).resolve().hasCompletedSetup)
    }

    @Test func interruptedRejoinPreservesImportRecoveryAndUsesTheCommittedIdentity() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let original = try store.confirmInitialRecording(isEnabled: true)
        let completion = BackupCoordinator.OnboardingImportCompletion(transactionID: UUID())
        try store.recordOnboardingImportCompletion(completion)
        let replacement = InstallationRecordingIdentity(
            deviceID: .init(rawValue: Self.resetDeviceID),
            registeredAt: Self.resetRegisteredAt,
            creation: .rejoin,
        )
        try fixture.identityStore.replace(replacement, expectedDeviceID: original.currentDevice.id)
        let recovered = fixture.makeStore(ids: [], dates: [])
        let context = try recovered.resolve()
        #expect(context.currentDevice.id == replacement.deviceID)
        #expect(context.automaticRecordingEnabled == nil)
        #expect(context.isRejoining)
        #expect(recovered.onboardingImportCompletion == completion)
        #expect(try recovered.rejoin() == context)
        #expect(fixture.identityStore.replacementCount == 1)
    }

    @Test func interruptedResetCannotRecoverOldConsentOrImportAuthority() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let original = try store.confirmInitialRecording(isEnabled: true)
        try store.recordOnboardingImportCompletion(.init(transactionID: UUID()))
        let replacement = InstallationRecordingIdentity(
            deviceID: .init(rawValue: Self.resetDeviceID),
            registeredAt: Self.resetRegisteredAt,
            creation: .reset,
        )
        try fixture.identityStore.replace(replacement, expectedDeviceID: original.currentDevice.id)
        let recovered = fixture.makeStore(ids: [], dates: [])
        #expect(try recovered.resolve().currentDevice.id == replacement.deviceID)
        #expect(try recovered.resolve().automaticRecordingEnabled == nil)
        #expect(recovered.onboardingImportCompletion == nil)
        #expect(fixture.fileExists == false)
        #expect(try fixture.makeStore(ids: [], dates: []).resolve().currentDevice.id == replacement
            .deviceID)
        #expect(fixture.identityStore.replacementCount == 1)
    }

    @Test func rejoinSidecarFailureRetainsTheCommittedIdentityAcrossRetryAndRelaunch() throws {
        let fixture = try makeFixture(
            ids: [Self.deviceID, Self.resetDeviceID],
            dates: [Self.registeredAt, Self.registeredAt, Self.resetRegisteredAt],
        )
        defer { fixture.cleanup() }
        let fileManager = FailingInstallationSidecarFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        _ = try store.confirmInitialRecording(isEnabled: true)
        let completion = BackupCoordinator.OnboardingImportCompletion(transactionID: UUID())
        try store.recordOnboardingImportCompletion(completion)
        fileManager.failNextWrite()

        #expect(throws: CocoaError.self) { try store.rejoin() }

        #expect(fixture.identityStore.identity?.deviceID.rawValue == Self.resetDeviceID)
        let relaunched = fixture.makeStore(ids: [], dates: [])
        let recovered = try relaunched.resolve()
        #expect(recovered.currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(recovered.automaticRecordingEnabled == nil)
        #expect(recovered.isRejoining)
        #expect(relaunched.onboardingImportCompletion == completion)
        #expect(try store.rejoin() == recovered)
        #expect(fixture.identityStore.replacementCount == 1)
    }

    @Test func mapsInterfaceIdiomsToRecordingKinds() {
        #expect(FileInstallationRecordingContextStore.kind(for: .phone) == .phone)
        #expect(FileInstallationRecordingContextStore.kind(for: .pad) == .tablet)
        #expect(FileInstallationRecordingContextStore.kind(for: .mac) == .computer)
        #expect(FileInstallationRecordingContextStore.kind(for: .tv) == .other("tv"))
    }

    @Test func proposedContextLeavesNoDurableMark() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let store = fixture.makeStore()

        #expect(try store.onboardingContext.currentDevice.id.rawValue == Self.deviceID)
        #expect(try store.onboardingContext.registeredAt == Self.registeredAt)
        #expect(try store.onboardingContext.automaticRecordingEnabled == nil)
        #expect(fixture.fileExists == false)
    }

    @Test func confirmationPersistsIdentityAndLocalChoiceTogether() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = fixture.makeStore()

        let confirmed = try first.confirmInitialRecording(isEnabled: false)
        let relaunched = fixture.makeStore()
        let restored = try relaunched.resolve()

        #expect(restored == confirmed)
        #expect(restored.currentDevice.id.rawValue == Self.deviceID)
        #expect(restored.registeredAt == Self.registeredAt)
        #expect(restored.automaticRecordingEnabled == false)
        #expect(
            try fixture.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true,
        )
        #expect(
            try fixture.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true,
        )
    }

    @Test func repeatedResolutionAndConfirmationReuseTheSameContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()

        let first = try store.confirmInitialRecording(isEnabled: true)
        let second = try store.confirmInitialRecording(isEnabled: true)

        #expect(try store.resolve() == first)
        #expect(second == first)
    }

    @Test func latestEnableCutoffSurvivesStoreRecreation() throws {
        let enabledAt = Self.registeredAt.addingTimeInterval(100)
        let fixture = try makeFixture(dates: [Self.registeredAt, Self.registeredAt, enabledAt])
        defer { fixture.cleanup() }
        let store = fixture.makeStore()

        _ = try store.confirmInitialRecording(isEnabled: false)
        try store.setAutomaticRecordingEnabled(true)

        #expect(try fixture.makeStore().resolve().recordingEnabledAt == enabledAt)
    }

    @Test func importRecoveryTransitionsSurviveStoreRecreation() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = try store.confirmInitialRecording(isEnabled: true)
        let details = try BackupCoordinator.ImportRecoveryDetails(
            transactionID: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
            installationID: RecordingDeviceID(rawValue: Self.deviceID),
            strategy: .replace,
            summary: BackupCoordinator.ImportSummary(
                sampleCount: 3,
                evidenceCount: 2,
                manualDayCount: 1,
                dismissedIssueCount: 0,
                trackedRegionCount: 4,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )

        try store.setBackupImportRecovery(.prepared(details))
        #expect(fixture.makeStore().backupImportRecovery == .prepared(details))

        let committed = BackupCoordinator.DurableImportRecovery.committed(
            details,
            cleanupCompleted: false,
            onboardingAcknowledged: true,
        )
        try store.setBackupImportRecovery(committed)

        #expect(fixture.makeStore().backupImportRecovery == committed)
    }

    @Test(arguments: [false, true])
    func completedOnboardingImportRepairsLostPreferenceAfterStoreRecreation(
        setupCompleted: Bool,
    ) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let installationStore = fixture.makeStore()
        let installationContext = try installationStore.confirmInitialRecording(isEnabled: true)
        let details = try BackupCoordinator.ImportRecoveryDetails(
            transactionID: #require(UUID(
                uuidString: "11111111-2222-3333-4444-555555555555",
            )),
            installationID: installationContext.currentDevice.id,
            strategy: .replace,
            summary: BackupCoordinator.ImportSummary(
                sampleCount: 3,
                evidenceCount: 2,
                manualDayCount: 1,
                dismissedIssueCount: 0,
                trackedRegionCount: 4,
                recordingDeviceCount: 0,
                recordingDeviceRemovalCount: 0,
            ),
        )
        try installationStore.setBackupImportRecovery(.committed(
            details,
            cleanupCompleted: true,
            onboardingAcknowledged: false,
        ))
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            installationContext: installationContext,
            importRecoveryPersistence: installationStore,
        )
        let acknowledgedPreferences = makePreferences()
        let acknowledgedModel = WhereModel(
            preferences: acknowledgedPreferences,
            installationContextStore: installationStore,
            makeBootstrap: { _ in ScriptedBootstrap(services: services) },
            logSystem: .isolated(),
        )
        acknowledgedModel.completeOnboarding()
        if setupCompleted {
            try installationStore.completeSetup()
        }

        try await services.backup.acknowledgeOnboardingImport()

        #expect(installationStore.backupImportRecovery == nil)
        #expect(installationStore.onboardingImportCompletion?.transactionID == details
            .transactionID)

        // Simulate a fresh process whose UserDefaults setter never reached disk. Recreating the
        // file-backed sidecar retains the terminal proof, so the gate repairs the preference and
        // cannot present Restore again.
        let relaunchedStore = fixture.makeStore()
        let lostPreferences = makePreferences()
        let relaunchedModel = WhereModel(
            preferences: lostPreferences,
            installationContextStore: relaunchedStore,
            makeBootstrap: { _ in UnusedBootstrap() },
            logSystem: .isolated(),
        )

        let isNeeded = try await OnboardingGate(model: relaunchedModel)
            .isNeeded(.installation(relaunchedModel.installationRecordingContext))

        #expect(isNeeded == !setupCompleted)
        #expect(relaunchedModel.hasOnboarded)
        #expect(relaunchedStore.backupImportRecovery == nil)
        #expect(relaunchedStore.onboardingImportCompletion?.transactionID == details.transactionID)
    }

    @Test func laterConfirmationCannotRewriteTheInitialChoice() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()

        let first = try store.confirmInitialRecording(isEnabled: false)
        let repeated = try store.confirmInitialRecording(isEnabled: true)

        #expect(repeated == first)
        #expect(repeated.automaticRecordingEnabled == false)
        #expect(try fixture.makeStore().resolve() == first)
    }

    @Test func launchPromotesACompletePendingFirstWriteAfterACrash() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let confirmed = try fixture.makeStore().confirmInitialRecording(isEnabled: false)
        try FileManager.default.moveItem(at: fixture.fileURL, to: fixture.pendingURL)

        let restored = try fixture.makeStore().resolve()

        #expect(restored == confirmed)
        #expect(fixture.fileExists)
        #expect(fixture.pendingExists == false)
    }

    @Test func completePendingReplacementWinsOverAnOlderAuthoritativeContext() throws {
        let oldFixture = try makeFixture()
        let newFixture = try makeFixture(
            ids: [Self.deviceID],
            dates: [Self.registeredAt, Self.registeredAt],
        )
        defer {
            oldFixture.cleanup()
            newFixture.cleanup()
        }
        _ = try oldFixture.makeStore().confirmInitialRecording(isEnabled: true)
        let replacement = try newFixture.makeStore().confirmInitialRecording(isEnabled: false)
        try FileManager.default.copyItem(at: newFixture.fileURL, to: oldFixture.pendingURL)

        let restored = try oldFixture.makeStore().resolve()

        #expect(restored == replacement)
        #expect(oldFixture.pendingExists == false)
    }

    @Test func corruptPendingReplacementIsDiscardedWithoutLosingTheLastGoodContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let confirmed = try fixture.makeStore().confirmInitialRecording(isEnabled: true)
        try Data("not-json".utf8).write(to: fixture.pendingURL)

        let restored = try fixture.makeStore().resolve()

        #expect(restored == confirmed)
        #expect(fixture.pendingExists == false)
    }

    @Test func resetRemovesTheSidecarAndRotatesTheInstallationIdentity() throws {
        let fixture = try makeFixture(ids: [
            Self.deviceID,
            Self.resetDeviceID,
        ], dates: [
            Self.registeredAt,
            Self.registeredAt,
            Self.resetRegisteredAt,
        ])
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = try store.confirmInitialRecording(isEnabled: true)
        try store.recordOnboardingImportCompletion(.init(transactionID: UUID()))

        try store.reset()

        #expect(fixture.fileExists == false)
        #expect(store.onboardingImportCompletion == nil)
        #expect(try store.onboardingContext.currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(try store.onboardingContext.registeredAt == Self.resetRegisteredAt)
        #expect(try store.onboardingContext.automaticRecordingEnabled == nil)
    }

    @Test func rejoinPersistsANewIdentityWithRecordingDefaultedOff() throws {
        let fixture = try makeFixture(
            ids: [Self.deviceID, Self.resetDeviceID],
            dates: [Self.registeredAt, Self.registeredAt, Self.resetRegisteredAt],
        )
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = try store.confirmInitialRecording(isEnabled: true)

        let rejoined = try store.rejoin()
        let relaunched = try fixture.makeStore().resolve()

        #expect(rejoined.currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(rejoined.automaticRecordingEnabled == nil)
        #expect(rejoined.isRejoining)
        #expect(rejoined.recommendedRecordingEnabled == false)
        #expect(relaunched == rejoined)
    }

    @Test func committedResetCleanupRetriesWithoutRestoringTheOldContextOrRotatingAgain() throws {
        let fixture = try makeFixture(ids: [
            Self.deviceID,
            Self.resetDeviceID,
        ], dates: [
            Self.registeredAt,
            Self.registeredAt,
            Self.resetRegisteredAt,
        ])
        defer { fixture.cleanup() }
        let fileManager = FailingResetCleanupFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        _ = try store.confirmInitialRecording(isEnabled: true)

        #expect(throws: WhereServices.ResetCleanupError.self) {
            try store.reset()
        }

        #expect(fixture.fileExists == false)
        #expect(fixture.resetPendingExists)
        #expect(fixture.identityStore.identity?.deviceID.rawValue == Self.resetDeviceID)
        #expect(throws: WhereServices.ResetCleanupError.self) {
            try store.resolve()
        }

        try store.reset()

        #expect(fixture.resetPendingExists == false)
        #expect(try store.onboardingContext.currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(fixture.identityStore.replacementCount == 1)
    }

    private nonisolated static let deviceID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    )!
    private nonisolated static let resetDeviceID = UUID(
        uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
    )!
    private nonisolated static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
    private nonisolated static let resetRegisteredAt = Date(timeIntervalSinceReferenceDate: 300)

    private func makeFixture(
        ids: [UUID] = [Self.deviceID],
        dates: [Date] = [Self.registeredAt, Self.registeredAt],
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "InstallationRecordingContextStoreTests.\(UUID().uuidString)")
        return Fixture(
            directory: directory,
            fileURL: directory.appending(path: "recording-installation-context.json"),
            ids: ids,
            dates: dates,
        )
    }

    private final class IDSequence {
        private var ids: [UUID]

        init(_ ids: [UUID]) {
            self.ids = ids
        }

        func next() -> UUID {
            precondition(ids.isEmpty == false, "Fixture requested more UUIDs than provided.")
            return ids.removeFirst()
        }
    }

    private final class DateSequence {
        private var dates: [Date]

        init(_ dates: [Date]) {
            self.dates = dates
        }

        func next() -> Date {
            precondition(dates.isEmpty == false, "Fixture requested more dates than provided.")
            return dates.removeFirst()
        }
    }

    @MainActor
    private struct Fixture {
        let identityStore = ScriptedRecordingIdentityStore()
        let directory: URL
        let fileURL: URL
        let ids: [UUID]
        let dates: [Date]

        var fileExists: Bool {
            FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
        }

        var pendingURL: URL {
            fileURL.appendingPathExtension("pending")
        }

        var pendingExists: Bool {
            FileManager.default.fileExists(atPath: pendingURL.path(percentEncoded: false))
        }

        var resetPendingURL: URL {
            directory.appendingPathExtension("reset-pending")
        }

        var resetPendingExists: Bool {
            FileManager.default.fileExists(
                atPath: resetPendingURL.path(percentEncoded: false),
            )
        }

        @MainActor
        func makeStore(
            fileManager: FileManager = .default,
            ids: [UUID]? = nil,
            dates: [Date]? = nil,
        ) -> FileInstallationRecordingContextStore {
            let sequence = IDSequence(ids ?? self.ids)
            let clock = DateSequence(dates ?? self.dates)
            return FileInstallationRecordingContextStore(
                identityStore: identityStore,
                fileURL: fileURL,
                fileManager: fileManager,
                systemName: "iPhone",
                kind: .phone,
                makeUUID: sequence.next,
                now: clock.next,
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: resetPendingURL)
        }
    }
}

private final class FailingResetCleanupFileManager: FileManager, @unchecked Sendable {
    private var shouldFailResetCleanup = true

    override func removeItem(at url: URL) throws {
        if shouldFailResetCleanup, url.pathExtension == "reset-pending" {
            shouldFailResetCleanup = false
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: url)
    }
}

extension InstallationRecordingContextStoreTests {
    @Test func onePhoneChangingAccountsCannotReuseItsGrantOrAffectTheOtherPhone() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 2) { phones in
            let first = try phones[0].launch()
            let second = try phones[1].launch()
            try await first.confirmAndStart(recording: false)
            try await second.confirmAndStart(recording: false)
            let firstServices = try first.services
            let secondServices = try second.services
            let identity = try first.context.resolve()
            let otherAccount = InstallationSharedAccount()
            await phones[0].connection.switchAccount(to: otherAccount)
            await first.model.refreshDataCompatibilityIfNeeded()
            #expect(firstServices.isDataAccessRevoked)
            #expect(first.model.compatibility
                .blockingError as? DataCompatibilityError == .accountChanged)
            #expect(try first.context.resolve() == identity)
            await second.model.refreshDataCompatibilityIfNeeded()
            try secondServices.validateDataAccess()
            #expect(await otherAccount.successfulSaves == 0)
            #expect(await phones[0].account.successfulSaves == 1)
        }
    }

    @Test func fixtureStartRejectsAnUnexpectedConsentGate() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let process = try phones[0].launch()
            await #expect(throws: InstallationLifecycleFixture.HistoryNotOpened.self) {
                try await process.start()
            }
            #expect(process.model.session == nil)
            #expect(process.bootstrap.locationSource == nil)
        }
    }

    @Test func restoredPreferencesCannotBypassRenewedConsentDuringRealFileLaunch() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 2) { phones in
            let original = try phones[0].launch()
            try await original.confirmAndStart(recording: true)
            let backup = try await phones[0].backup()
            defer { backup.cleanup() }
            try await phones[1].replaceFiles(with: backup)
            let restored = try phones[1].launch()
            #expect(restored.model.preferences.hasOnboarded)
            let launcher = WhereLaunch.makeLauncher(model: restored.model, reason: .userForeground)
            let drive = Task { await launcher.run() }
            do {
                try await CompatibilityLaunchFixture.waitUntil { launcher.phase.gateHandle != nil }
                #expect(launcher.phase.gateHandle?.id == AnyHashable(LaunchStepID.onboarding))
                #expect(restored.model.session == nil)
                #expect(restored.bootstrap.locationSource == nil)
                #expect(phones[1].keychain.identity == nil)
                try restored.model.confirmInitialRecordingChoice(isEnabled: false)
                try restored.model.completeInstallationSetup()
                restored.model.completeOnboarding()
                launcher.phase.gateHandle?.complete()
                try await CompatibilityLaunchFixture.waitUntil { launcher.phase.isReady }
            } catch {
                await phones[1].account.releaseInitialSaves()
                launcher.phase.gateHandle?.fail(error)
                drive.cancel()
                await drive.value
                throw error
            }
            await drive.value
            #expect(try restored.context.resolve().hasCompletedSetup)
            #expect(try restored.context.resolve().automaticRecordingEnabled == false)
        }
    }

    @Test func reorderedHistoryDeliveryPreservesSourceAndRejectsUnsupportedRecordsBeforeControl(
    ) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 2) { phones in
            let producer = try phones[0].launch()
            let receiver = try phones[1].launch()
            try await producer.confirmAndStart(recording: true)
            try await receiver.confirmAndStart(recording: false)
            let sourceID = try producer.context.resolve().currentDevice.id
            let source = try #require(producer.bootstrap.locationSource)
            // Enter through production ingestion, which stamps the current recording identity.
            let input = LocationSample(
                timestamp: phones[0].instant.addingTimeInterval(10),
                coordinate: .init(latitude: 40, longitude: -74),
                horizontalAccuracy: 5,
                source: .gpsVisit,
            )
            source.emit(input)
            try await InstallationLifecycleFixture.waitUntil {
                try await producer.store.allSamples().count == 1
            }
            let sample = try #require(await producer.store.allSamples().first)
            #expect(sample.recordingDeviceID == sourceID)
            let samples = InstallationHistoryDelivery(
                samples: [sample],
                profiles: [],
                removals: [],
                records: [],
            )
            try await samples.commit(
                to: receiver.store,
                remoteChanges: receiver.bootstrap.remoteChanges,
            )
            try await samples.commit(
                to: receiver.store,
                remoteChanges: receiver.bootstrap.remoteChanges,
            )
            #expect(try await receiver.store.allSamples() == [sample])
            let profiles = try await producer.store.recordingDeviceProfiles()
            try await InstallationHistoryDelivery(
                samples: [],
                profiles: profiles,
                removals: [],
                records: [],
            )
            .commit(to: receiver.store, remoteChanges: receiver.bootstrap.remoteChanges)
            #expect(try await receiver.store.recordingDeviceProfiles()
                .contains { $0.id == sourceID })
            let admittedServices = try receiver.services
            let futureRecord = try await VersionedHistoryRecord(
                id: .init(rawValue: UUID()),
                dataGenerationID: receiver.store.dataGeneration().id,
                semantics: .init(major: 1, minor: 0, patch: 0),
                kind: "future-fixture-record",
                payload: Data([0xFF]),
            )
            try await InstallationHistoryDelivery(
                samples: [],
                profiles: [],
                removals: [],
                records: [futureRecord],
            )
            .commit(to: receiver.store, remoteChanges: receiver.bootstrap.remoteChanges)
            try await CompatibilityLaunchFixture.waitUntil { admittedServices.isDataAccessRevoked }
            #expect(try await phones[0].account.head(accountID: phones[0].account.accountID())?
                .requiredMajor == 0)
            await #expect(throws: DataCompatibilityAccess.AccessError.self) {
                try await admittedServices.journal.addManualSample(LocationSample(
                    timestamp: phones[1].instant,
                    coordinate: .init(latitude: 41, longitude: -74),
                    horizontalAccuracy: 0,
                    source: .manual,
                ))
            }
            #expect(try await receiver.store.allSamples() == [sample])
        }
    }

    @Test func stoppedFixtureProcessReleasesItsDatasetOwner() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            weak var previousBootstrap: InstallationBootstrapFixture?
            weak var previousModel: WhereModel?
            do {
                let process = try phones[0].launch()
                try await process.confirmAndStart(recording: false)
                previousBootstrap = process.bootstrap
                previousModel = process.model
                try await phones[0].stop()
            }
            try await CompatibilityLaunchFixture.waitUntil {
                previousBootstrap == nil && previousModel == nil
            }
        }
    }

    @Test func systemRestoreCannotReuseTheOrdinaryRelaunchOfflineGrant() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: false)
            let backup = try await phone.backup()
            defer { backup.cleanup() }
            await phone.account.setOnline(false)
            let ordinary = try phone.launch()
            let ordinaryCoordinator = try #require(ordinary.bootstrap.prepareDataCompatibility())
            let offlineAccess = try await ordinaryCoordinator.refresh()
            try offlineAccess.validate()

            try await phone.replaceFiles(with: backup)
            let restored = try phone.launch()
            let restoredCoordinator = try #require(restored.bootstrap.prepareDataCompatibility())
            await #expect(throws: CKError.self) {
                try await restoredCoordinator.refresh()
            }
            #expect(restored.bootstrap.store == nil)
            await phone.account.setOnline(true)
            try await restored.confirmAndStart(recording: false)
            try restored.services.validateDataAccess()
        }
    }

    @Test func lostInitializationResponseRecoversTheSameSharedHead() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let first = try phone.launch()
            let coordinator = try #require(first.bootstrap.prepareDataCompatibility())
            await phone.account.loseNextSaveResponse()
            await #expect(throws: CKError.self) {
                try await coordinator.refresh()
            }
            #expect(first.bootstrap.store == nil)
            #expect(await phone.account.successfulSaves == 1)
            try await phone.stop()
            let recovered = try phone.launch()
            try await recovered.confirmAndStart(recording: false)
            #expect(await phone.account.successfulSaves == 1)
        }
    }

    @Test func resetRotatesTheRealSidecarIdentityAndRequestsConsentAgain() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: true)
            let originalID = try original.context.resolve().currentDevice.id
            let sample = original.sample(recordedBy: originalID)
            try await original.store.perform { try await original.store.add(sample: sample) }
            try await original.services.reset()
            try original.model.resetPreferences()
            await original.model.endSession()
            try await phone.stop()
            let reset = try phone.launch()
            let next = try reset.context.resolve()
            #expect(next.currentDevice.id != originalID)
            #expect(next.automaticRecordingEnabled == nil)
            #expect(!next.hasCompletedSetup)
            #expect(!reset.model.preferences.hasOnboarded)
            try await reset.confirmAndStart(recording: false)
            #expect(try await reset.store.allSamples().isEmpty)
            #expect(phone.keychain.replacementCount == 1)
        }
    }

    @Test func ordinaryProcessReplacementPreservesConfirmedIdentityAndDiskHistory() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: true)
            let context = try original.context.resolve()
            let sample = original.sample(recordedBy: context.currentDevice.id)
            try await original.store.perform { try await original.store.add(sample: sample) }
            try await phone.stop()

            let updated = try phone.launch()
            #expect(try updated.context.resolve() == context)
            #expect(updated.model.preferences.hasOnboarded)
            try await updated.start()
            #expect(try await updated.store.allSamples() == [sample])
            #expect(phone.keychain.creationCount == 1)
            #expect(phone.allocatedIdentities.count == 1)
        }
    }

    @Test(arguments: [false, true])
    func copiedAppFilesNeverRestoreConsentOnTheSamePhone(restoreBackup: Bool) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: true)
            let context = try original.context.resolve()
            let sample = original.sample(recordedBy: context.currentDevice.id)
            try await original.store.perform { try await original.store.add(sample: sample) }
            let queue = try #require(original.bootstrap.sharedEvidenceDraftQueue())
            try await queue.enqueue(SharedEvidenceQueueFixture.draft())
            let backup = try await phone.backup()
            defer { backup.cleanup() }
            // These are actual files created by production adapters, not a fixture allowlist.
            #expect(!FileManager.default
                .fileExists(atPath: backup.directory.appending(path: "Installation").path))
            #expect(!FileManager.default
                .fileExists(atPath: backup.directory.appending(path: "Compatibility").path))
            #expect(!FileManager.default
                .fileExists(atPath: backup.directory.appending(path: "PendingSharedEvidence").path))
            #expect(FileManager.default
                .fileExists(atPath: backup.directory.appending(path: "Preferences.plist").path))
            #expect(FileManager.default
                .fileExists(atPath: backup.directory.appending(path: "History/Where.store").path))

            phone.instant += 86400
            try await phone.replaceFiles(with: restoreBackup ? backup : nil)
            let recovered = try phone.launch()
            let proposal = try recovered.context.resolve()
            #expect(proposal.currentDevice.id == context.currentDevice.id)
            #expect(proposal.registeredAt == context.registeredAt)
            #expect(proposal.automaticRecordingEnabled == nil)
            #expect(!proposal.hasCompletedSetup)
            #expect(recovered.model.preferences.hasOnboarded == restoreBackup)
            try await recovered.confirmAndStart(recording: true)
            #expect(try recovered.context.resolve().recordingEnabledAt == phone.instant)
            #expect(try await recovered.store.allSamples() == (restoreBackup ? [sample] : []))
            #expect(phone.keychain.creationCount == 1)
        }
    }

    @Test func newPhoneRestoreAndTransferKeepHistoricalAttributionWithoutCopyingIdentity(
    ) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 3) { phones in
            let source = try phones[0].launch()
            try await source.confirmAndStart(recording: true)
            let identity = try source.context.resolve().currentDevice.id
            let sample = source.sample(recordedBy: identity)
            try await source.store.perform { try await source.store.add(sample: sample) }
            let backup = try await phones[0].backup()
            defer { backup.cleanup() }
            var identities: Set<RecordingDeviceID> = [identity]
            // Restore and direct transfer use the same explicitly documented backup boundary:
            // device-only Keychain and backup-excluded directories do not transfer.
            for phone in phones.dropFirst() {
                try await phone.replaceFiles(with: backup)
                let target = try phone.launch()
                let context = try target.context.resolve()
                #expect(identities.insert(context.currentDevice.id).inserted)
                #expect(context.automaticRecordingEnabled == nil)
                #expect(!context.hasCompletedSetup)
                #expect(target.model.preferences.hasOnboarded)
                try await target.confirmAndStart(recording: false)
                #expect(try await target.store.allSamples() == [sample])
                #expect(phone.keychain.creationCount == 1)
                #expect(try await target.store.recordingDevices().contains { $0.id == identity })
            }
        }
    }

    @Test func keychainFailureAllocatesNothingAndMissingIdentityCannotAdoptCopiedSidecar(
    ) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: true)
            let context = try original.context.resolve()
            try await phone.stop()
            phone.keychain.failure = .unavailable
            let locked = try phone.launch()
            #expect(throws: ScriptedRecordingIdentityStore.Failure.self) {
                try locked.context.resolve()
            }
            #expect(phone.allocatedIdentities.count == 1)
            #expect(locked.bootstrap.store == nil)
            phone.keychain.failure = nil
            #expect(try locked.context.resolve() == context)
            try await phone.stop()
            phone.keychain.identity = nil
            let missing = try phone.launch()
            let proposed = try missing.context.resolve()
            #expect(proposed.currentDevice.id != context.currentDevice.id)
            #expect(proposed.automaticRecordingEnabled == nil)
            #expect(!proposed.hasCompletedSetup)
            #expect(missing.model.preferences.hasOnboarded)
            #expect(phone.keychain.identity == nil)
            try await missing.confirmAndStart(recording: false)
            #expect(phone.keychain.creationCount == 2)
        }
    }

    @Test(arguments: [BackupCoordinator.ImportStrategy.merge, .replace])
    func userArchiveImportsPreserveTheReceivingPhonesIdentityAndConsent(
        strategy: BackupCoordinator.ImportStrategy,
    ) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 2) { phones in
            let source = try phones[0].launch()
            let target = try phones[1].launch()
            try await source.confirmAndStart(recording: true)
            try await target.confirmAndStart(recording: false)
            let sourceContext = try source.context.resolve()
            let targetContext = try target.context.resolve()
            let sample = source.sample(recordedBy: sourceContext.currentDevice.id)
            try await source.store.perform { try await source.store.add(sample: sample) }
            let archive = try await source.services.backup.exportBackup(onProgress: { _ in })
            defer {
                do { try FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
                catch { Issue.record(error) }
            }
            _ = try await target.services.backup.importBackup(
                from: archive,
                strategy: strategy,
                onProgress: { _ in },
            )
            try await target.services.backup.acknowledgeOnboardingImport()
            #expect(try target.context.resolve() == targetContext)
            #expect(try await target.store.allSamples() == [sample])
            try await phones[1].stop()
            let relaunched = try phones[1].launch()
            #expect(try relaunched.context.resolve() == targetContext)
            try await relaunched.start()
            #expect(try await relaunched.store.allSamples() == [sample])
            #expect(phones[1].keychain.creationCount == 1)
        }
    }

    @Test func restoredRemovedIdentityRequiresExplicitRejoinAndPreservesOldSampleProvenance(
    ) async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 1) { phones in
            let phone = phones[0]
            let original = try phone.launch()
            try await original.confirmAndStart(recording: true)
            let originalID = try original.context.resolve().currentDevice.id
            let sample = original.sample(recordedBy: originalID)
            try await original.store.perform { try await original.store.add(sample: sample) }
            // Simulate a tombstone arriving from another installation through the value-store
            // boundary. The local controller intentionally cannot remove its own identity.
            let removal = RecordingDeviceRemoval(
                id: .init(rawValue: UUID()),
                deviceID: originalID,
                removedAt: phone.instant.addingTimeInterval(60),
                removedByDeviceID: .init(rawValue: UUID()),
            )
            try await original.store
                .perform { try await original.store.addRecordingDeviceRemoval(removal) }
            let backup = try await phone.backup()
            defer { backup.cleanup() }
            try await phone.replaceFiles(with: backup)
            let restored = try phone.launch()
            #expect(try restored.context.resolve().currentDevice.id == originalID)
            try await restored.confirmAndStart(recording: true)
            #expect(try await restored.services.recording.currentRuntimeUpdate()?.state == .removed)
            try await restored.model.rejoinInstallation()
            let rejoined = try restored.context.resolve()
            #expect(rejoined.currentDevice.id != originalID)
            #expect(rejoined.automaticRecordingEnabled == nil)
            #expect(!rejoined.recommendedRecordingEnabled)
            #expect(try await restored.store.allSamples() == [sample])
            #expect(phone.keychain.replacementCount == 1)
        }
    }

    @Test func independentInstallationsShareControlAndRejectObsoleteScopeWrites() async throws {
        try await InstallationLifecycleFixture.withInstallations(count: 2) { phones in
            let first = try phones[0].launch()
            let second = try phones[1].launch()
            let account = phones[0].account
            await account.holdInitialSaves()
            let startFirst = Task { try await first.confirmAndStart(recording: false) }
            let startSecond = Task { try await second.confirmAndStart(recording: false) }
            do {
                try await InstallationLifecycleFixture.waitUntil {
                    await account.pendingInitialSaveCount == 2
                }
            } catch {
                startFirst.cancel()
                startSecond.cancel()
                await account.releaseInitialSaves()
                _ = await (startFirst.result, startSecond.result)
                throw error
            }
            await account.releaseInitialSaves()
            let firstResult = await startFirst.result
            let secondResult = await startSecond.result
            try firstResult.get()
            try secondResult.get()
            #expect(await phones[0].account.successfulSaves == 1)
            #expect(await account.conditionalConflicts == 1)
            #expect(try first.context.resolve().currentDevice.id != second.context.resolve()
                .currentDevice.id)
            let oldServices = try first.services
            try await phones[0].account.requireMajor(1)
            await first.model.refreshDataCompatibilityIfNeeded()
            #expect(oldServices.isDataAccessRevoked)
            await #expect(throws: DataCompatibilityAccess.AccessError.self) {
                try await oldServices.journal.addManualSample(LocationSample(
                    timestamp: phones[0].instant,
                    coordinate: .init(latitude: 40, longitude: -74),
                    horizontalAccuracy: 0,
                    source: .manual,
                ))
            }
            #expect(try await first.store.allSamples().isEmpty)
            #expect(try first.context.resolve().automaticRecordingEnabled == false)
            let secondServices = try second.services
            await second.model.refreshDataCompatibilityIfNeeded()
            #expect(secondServices.isDataAccessRevoked)
        }
    }
}
