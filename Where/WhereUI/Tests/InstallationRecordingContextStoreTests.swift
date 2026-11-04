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
