import Foundation
import TestHostSupport
import Testing
@testable import WhereCore

@MainActor
struct DataCompatibilityCoordinatorTests {
    private let deviceID = RecordingDeviceID(rawValue: UUID())
    private let offline = DataCompatibilityTransportError
        .unavailable(URLError(.notConnectedToInternet))

    @Test(arguments: [nil, 1])
    func baselineViewersOpenWithoutPublishing(shared: Int?) async {
        let transport = ScriptedDataCompatibilityTransport(version: shared)
        let receipts = InMemoryDataCompatibilityReceipt()
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore)
        #expect(await transport.saveCount == 0)
        #expect(receipts.receipt?.access == .verified)
    }

    @Test func newerDataLocksEveryDevice() async {
        let transport = ScriptedDataCompatibilityTransport(version: 3)
        let receipts = InMemoryDataCompatibilityReceipt()
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .recording(deviceID) }
        guard case .blocked(.updateRequired(.init(rawValue: 3), reason: nil)) = coordinator.state
        else {
            Issue.record("Newer shared data must block this build"); return
        }
        #expect(await transport.saveCount == 0)
        #expect(receipts.receipt?.version.rawValue == 3)
        #expect(receipts.receipt?.access == .blocked)
    }

    @Test func newerDataReasonSurvivesRelaunchWithoutContactingCloud() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let reason =
            DataModelChangeReason(translations: ["en": "Location corrections use a new format."])
        await transport.setVersion(3, reason: reason)
        let receipts = InMemoryDataCompatibilityReceipt()

        for _ in 0 ..< 2 {
            let coordinator = DataCompatibilityCoordinator(
                transport: transport,
                receipts: receipts,
                version: .baseline,
            )
            await coordinator.refresh { .disabled }
            guard case let .blocked(.updateRequired(.init(rawValue: 3), observedReason)) =
                coordinator.state
            else {
                Issue.record("Newer shared data must block this build"); return
            }
            #expect(observedReason == reason)
            #expect(receipts.receipt?.changeReason == reason)
        }
        #expect(await transport.readCount == 1)
    }

    @Test func onlyRecorderCanAdvanceAndWaitingViewerRecovers() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let viewer = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .init(rawValue: 2),
        )
        await viewer.refresh { .disabled }
        guard case .blocked(.recordingDeviceRequired) = viewer.state else {
            Issue.record("An upgraded viewer must wait for the recording device"); return
        }
        #expect(await transport.saveCount == 0)
        let recorder = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .init(rawValue: 2),
        )
        await recorder.refresh { .recording(deviceID) }
        #expect(recorder.state.allowsStore)
        #expect(await transport.saveCount == 1)
        await viewer.refresh { .disabled }
        #expect(viewer.state.allowsStore)
    }

    @Test func canadianRegionWriterExplainsTheUpgradeToAnOlderViewer() async throws {
        let regionVersion = DataModelVersion(rawValue: 2)
        let reason = try #require(regionVersion.changeReason)
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt()
        let previous = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await previous.refresh { .disabled }
        let originalAdmission = try previous.requireAccess()
        let recorder = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: regionVersion,
        )
        await recorder.refresh { .recording(deviceID) }
        #expect(recorder.state.allowsStore)
        #expect(await transport.remote?.version == regionVersion)
        #expect(await transport.remote?.changeReason == reason)

        // An offline installation can only act on its last verified version.
        await transport.setReadError(offline)
        await previous.refresh { .disabled }
        guard case .offline = previous.state else {
            Issue
                .record(
                    "The previous build should retain its last verified offline admission",
                ); return
        }
        await transport.setReadError(nil)
        await previous.refresh { .disabled }
        guard case .blocked(.updateRequired(regionVersion, reason: reason)) = previous.state else {
            Issue.record("The older viewer must receive the reason for the upgrade"); return
        }
        #expect(throws: DataCompatibilityFailure.self) {
            try previous.requireAccess(originalAdmission)
        }
        #expect(receipts.receipt?.changeReason == reason)
        await transport.setReadError(offline)
        let relaunched = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await relaunched.refresh { .disabled }
        guard case .blocked(.updateRequired(regionVersion, reason: reason)) = relaunched.state
        else {
            Issue
                .record("The older viewer must retain the reason after an offline relaunch"); return
        }
        #expect(await transport.saveCount == 1)
    }

    @Test func missingPermissionCannotAdvance() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .permissionRequired }
        guard case .blocked(.locationPermissionRequired) = coordinator.state else {
            Issue.record("Expected permission recovery"); return
        }
        #expect(await transport.saveCount == 0)
    }

    @Test func offlineAccessSurvivesRelaunchButNotAnUpgrade() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt()
        let first = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await first.refresh { .disabled }
        await transport.setReadError(offline)
        let second = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await second.refresh { .disabled }
        guard case .offline = second.state
        else { Issue.record("Expected verified offline access"); return }
        let upgraded = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await upgraded.refresh { .recording(deviceID) }
        #expect(!upgraded.state.allowsStore)
    }

    @Test func uncertainUpgradeRequiresReadback() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt()
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await transport.setSaveError(offline)
        await coordinator.refresh { .recording(deviceID) }
        #expect(!coordinator.state.allowsStore)
        #expect(await transport.remote?.version.rawValue == 2)
        await coordinator.refresh { .recording(deviceID) }
        #expect(coordinator.state.allowsStore)
        #expect(await transport.saveCount == 1)
    }

    @Test func conflictWithNewerWriterBlocksInsteadOfDowngrading() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        await transport.conflict(with: 3)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .recording(deviceID) }
        #expect(!coordinator.state.allowsStore)
        #expect(await transport.remote?.version.rawValue == 3)
        #expect(await transport.saveCount == 1)
    }

    @Test func accountChangeRejectsSuspendedCompletion() async throws {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .baseline,
        )
        await transport.holdRead()
        let refresh = Task { await coordinator.refresh { .disabled } }
        try await waitForCompatibility { await transport.isReadHeld }
        await transport.changeAccount()
        try await waitForCompatibility {
            if case .blocked = coordinator.state {
                true
            } else {
                false
            }
        }
        await transport.releaseRead()
        await refresh.value
        #expect(!coordinator.state.allowsStore)
    }

    @Test func overlappingTriggersShareOneVerification() async throws {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .baseline,
        )
        await transport.holdRead()
        let first = Task { await coordinator.refresh { .disabled } }
        try await waitForCompatibility { await transport.isReadHeld }
        var secondEntered = false
        let second = Task {
            secondEntered = true
            await coordinator.refresh { .disabled }
        }
        try await waitForCompatibility { secondEntered }
        await transport.releaseRead()
        await first.value
        await second.value
        #expect(await transport.readCount == 1)
        #expect(coordinator.state.allowsStore)
    }

    @Test func accountNotificationBeforeFirstCheckPreservesTheCachedFloor() async throws {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt(receipt: .init(
            domain: .cloud(.init(containerIdentifier: "iCloud.test", userRecordName: "account-a")),
            version: .init(rawValue: 3),
            access: .verified,
            removedDeviceID: deviceID,
        ))
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await transport.changeAccount()
        try await waitForCompatibility { receipts.receipt?.access == .blocked }
        #expect(receipts.receipt?.version.rawValue == 3)
        #expect(receipts.receipt?.removedDeviceID == deviceID)
        await coordinator.refresh { .recording(deviceID) }
        #expect(!coordinator.state.allowsStore)
        #expect(await transport.saveCount == 0)
    }

    @Test func removedInstallationCannotPublishOnRelaunch() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt()
        let first = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await first.refresh { .recording(deviceID) }
        first.recordRemoval(of: deviceID)
        let next = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await next.refresh { .recording(deviceID) }
        #expect(!next.state.allowsStore)
        #expect(await transport.saveCount == 0)
    }

    @Test func receiptFailureDoesNotGrantAccess() async {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let receipts = InMemoryDataCompatibilityReceipt()
        receipts.failure = CocoaError(.fileReadCorruptFile)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .baseline,
        )
        await coordinator.refresh { .disabled }
        #expect(!coordinator.state.allowsStore)
        #expect(await transport.readCount == 0)
    }

    @Test(arguments: [nil, 1])
    func higherCacheCannotSubstituteForSharedPublication(shared: Int?) async {
        let transport = ScriptedDataCompatibilityTransport(version: shared)
        let receipts = InMemoryDataCompatibilityReceipt(receipt: .init(
            domain: .cloud(.init(containerIdentifier: "iCloud.test", userRecordName: "account-a")),
            version: .init(rawValue: 2),
            access: .verified,
            removedDeviceID: nil,
        ))
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .disabled }
        #expect(!coordinator.state.allowsStore)
        #expect(await transport.saveCount == 0)
        #expect(receipts.receipt?.access == .blocked)
    }

    @Test func localTransportStillRequiresVerificationAndPreservesTheFloor() async throws {
        let receipts = InMemoryDataCompatibilityReceipt()
        let newer = DataCompatibilityCoordinator(
            transport: LocalDataCompatibilityTransport(version: .init(rawValue: 2)),
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        #expect(newer.state.allowsStore == false)
        await newer.refresh { .disabled }
        #expect(try newer.requireAccess().domain == .local)
        #expect(receipts.receipt?.version.rawValue == 2)
        #expect(receipts.receipt?.access == .verified)
        let older = DataCompatibilityCoordinator(
            transport: LocalDataCompatibilityTransport(version: .baseline),
            receipts: receipts,
            version: .baseline,
        )
        await older.refresh { .recording(deviceID) }
        #expect(older.state.allowsStore == false)
        #expect(receipts.receipt?.version.rawValue == 2)
        #expect(receipts.receipt?.access == .blocked)
    }

    @Test func localReceiptCannotPublishOrProvideCloudOfflineAccess() async throws {
        let transport = ScriptedDataCompatibilityTransport(version: 2)
        await transport.setDomain(.local, notify: false)
        let receipts = InMemoryDataCompatibilityReceipt()
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .disabled }
        let localAdmission = try coordinator.requireAccess()
        await transport.setDomain(.cloud(.init(
            containerIdentifier: "iCloud.test",
            userRecordName: "account-a",
        )), notify: false)
        await transport.setVersion(1)
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore == false, "Domain changes first retire local access")
        await coordinator.refresh { .disabled }
        #expect(
            coordinator.state.allowsStore == false,
            "The local floor is not a remote publication",
        )
        #expect(await transport.saveCount == 0)
        await transport.setReadError(offline)
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore == false)
        await transport.setReadError(nil)
        await coordinator.refresh { .recording(deviceID) }
        #expect(coordinator.state.allowsStore)
        #expect(await transport.saveCount == 1)
        #expect(throws: DataCompatibilityFailure.self) {
            try coordinator.requireAccess(localAdmission)
        }
    }

    @Test func signedOutLocalModeCannotLowerACloudFloor() async {
        let receipts = InMemoryDataCompatibilityReceipt(receipt: .init(
            domain: .cloud(.init(containerIdentifier: "iCloud.test", userRecordName: "account-a")),
            version: .init(rawValue: 3),
            access: .verified,
            removedDeviceID: nil,
        ))
        let coordinator = DataCompatibilityCoordinator(
            transport: LocalDataCompatibilityTransport(version: .init(rawValue: 2)),
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore == false)
        #expect(receipts.receipt?.version.rawValue == 3)
    }

    @Test func returningToTheSameAccountDoesNotRestoreAnOldAdmission() async throws {
        let transport = ScriptedDataCompatibilityTransport(version: 1)
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: InMemoryDataCompatibilityReceipt(),
            version: .baseline,
        )
        await coordinator.refresh { .disabled }
        let original = try coordinator.requireAccess()
        await transport.setDomain(original.domain, notify: true)
        try await waitForCompatibility { coordinator.state.allowsStore == false }
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore)
        #expect(throws: DataCompatibilityFailure.self) { try coordinator.requireAccess(original) }
    }

    @Test func coldCloudVerificationCannotUseAVerifiedLocalReceiptOffline() async {
        let transport = ScriptedDataCompatibilityTransport(version: 2)
        await transport.setReadError(offline)
        let receipts = InMemoryDataCompatibilityReceipt(receipt: .init(
            domain: .local,
            version: .init(rawValue: 2),
            access: .verified,
            removedDeviceID: nil,
        ))
        let coordinator = DataCompatibilityCoordinator(
            transport: transport,
            receipts: receipts,
            version: .init(rawValue: 2),
        )
        await coordinator.refresh { .disabled }
        #expect(coordinator.state.allowsStore == false)
        #expect(receipts.receipt?.access == .blocked)
        #expect(await transport.saveCount == 0)
    }
}
