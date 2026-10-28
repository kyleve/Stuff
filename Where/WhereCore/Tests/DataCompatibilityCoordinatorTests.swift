import CloudKit
import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct DataCompatibilityCoordinatorTests {
    @Test func localHistoryCannotAuthorizeInitialAccess() async throws {
        let fixture = try CompatibilityAccountFixture()
        _ = try await fixture.recording.selectRecordingRole(.recordingRequested)
        let reads = await fixture.transport.readCount
        let identityReads = await fixture.transport.identityReadCount
        #expect(await fixture.coordinator.recheckLocalHistory() == .checking)
        #expect(await fixture.transport.readCount == reads)
        #expect(await fixture.transport.identityReadCount == identityReads)
        await #expect(throws: DataCompatibilityError.notReady) {
            _ = try await fixture.coordinator.openDomainStore()
        }
        #expect(await fixture.coordinator.recheck() == .compatible(.current))
        _ = try await fixture.coordinator.openDomainStore()
    }

    @Test func accountInvalidationBlocksOfflineCacheAndSurvivesRestart() async throws {
        let fixture = try CompatibilityAccountFixture()
        let oldScope = try await fixture.establish()
        await fixture.transport.setAvailability(.offline)
        #expect(await fixture.coordinator.recheck() == .compatible(.current))
        await fixture.coordinator.invalidateAccount()
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await oldScope.perform {}
        }
        guard case .verificationFailed = await fixture.coordinator.recheck() else {
            Issue.record("Invalidated authority must not authorize offline use."); return
        }
        let restarted = CompatibilityAccountFixture(
            store: fixture.store,
            transport: fixture.transport,
            installation: fixture.installation,
        )
        guard case .verificationFailed = await restarted.coordinator.recheck() else {
            Issue.record("Restart must not restore invalidated trust."); return
        }
        await fixture.transport.setAvailability(.online)
        #expect(await fixture.coordinator.recheck() == .compatible(.current))
        let freshScope = try await fixture.coordinator.openDomainStore()
        #expect(try await freshScope.allSamples().isEmpty)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await oldScope.perform {}
        }
    }

    @Test func oldAccountResponseCannotProjectHistoryOrRestoreAccess() async throws {
        let fixture = try CompatibilityAccountFixture()
        let oldScope = try await fixture.establish()
        let original = try await fixture.authority.observed()
        let originalCommits = try await fixture.store.recordingAuthorityCommits()
        _ = try await fixture.transport.commit(RecordingAuthorityProposal(
            state: original,
            action: .recover(.keep),
            deviceID: .init(rawValue: UUID()),
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        ))
        let gate = CompatibilityTestGate()
        await fixture.transport.holdNextRead(gate)
        let oldRequest = Task { await fixture.coordinator.recheck() }
        await gate.waitUntilEntered()
        await fixture.coordinator.invalidateAccount()
        await fixture.transport.setAvailability(.offline)
        gate.resume()
        guard case .verificationFailed = await oldRequest.value else {
            Issue.record("The old account's successful response must be discarded."); return
        }
        #expect(try await fixture.store.recordingAuthorityCommits() == originalCommits)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await oldScope.perform {}
        }
        guard case .verificationFailed = await fixture.coordinator.recheckLocalHistory() else {
            Issue.record("Local history cannot clear account invalidation."); return
        }
    }

    @Test func differentAccountCannotReadOrReplayOriginalPendingHandoff() async throws {
        let fixture = try CompatibilityAccountFixture()
        _ = try await fixture.establish()
        let original = try await fixture.authority.observed()
        let pending = try RecordingAuthorityProposal(
            state: original,
            action: .requestHandoff,
            deviceID: .init(rawValue: UUID()),
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        try fixture.installation.setRecordingControl(.init(
            selection: .recordingRequested,
            pendingTransition: pending,
        ))
        let commits = try await fixture.store.recordingAuthorityCommits()
        let reads = await fixture.transport.readCount
        await fixture.coordinator.invalidateAccount()
        await fixture.transport.setAccountID(.cloudKit(recordName: "account-b"))
        guard case .verificationFailed = await fixture.coordinator.recheck() else {
            Issue.record("A different account must stay blocked."); return
        }
        await #expect(throws: RecordingAccountError.differentAccount) {
            _ = try await fixture.recording.retryPendingRequest()
        }
        #expect(await fixture.transport.readCount == reads)
        #expect(try await fixture.store.recordingAuthorityCommits() == commits)
        #expect(try fixture.installation.resolve().recordingControl.pendingTransition == pending)
        await fixture.transport.setAccountID(.cloudKit(recordName: "account-a"))
        #expect(await fixture.coordinator.recheck() == .compatible(.current))
    }

    @Test(arguments: [CompatibilityRemoteChange.signedOut, .newerRequirement])
    func concurrentRetriesVerifyAuthorityWhileLocalHistoryRemainsAvailable(
        change: CompatibilityRemoteChange,
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = CompatibilityTestTransport()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: transport,
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let recording = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let owned = try await recording.selectRecordingRole(.recordingRequested)
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            recording: recording,
            installation: installation,
        )
        #expect(await coordinator.recheck() == .compatible(.current))
        let domain = try await coordinator.openDomainStore()
        // Hold a user operation so remote verification parks at waitUntilIdle().
        let gate = CompatibilityTestGate()
        await transport.holdNextRead(gate)
        let selection = Task { try await recording.selectRecordingRole(.secondary) }
        await gate.waitUntilEntered()
        defer { gate.resume() }
        let firstRemote = Task { await coordinator.recheck() }
        let secondRemote = Task { await coordinator.recheck() }
        try await waitForCompatibilityChecks(2, in: coordinator)
        #expect(await coordinator.recheckLocalHistory() == .compatible(.current))
        let reads = await transport.readCount
        let identityReads = await transport.identityReadCount
        let newerVersion = DataCompatibilityVersion(rawValue: 2)
        switch change {
            case .signedOut: await transport.setAvailability(.signedOut)
            case .newerRequirement:
                _ = try await transport.commit(RecordingAuthorityProposal(
                    state: owned,
                    action: .upgrade,
                    deviceID: installation.onboardingContext.currentDevice.id,
                    buildVersion: newerVersion,
                    eventID: .init(rawValue: UUID()),
                ))
        }
        gate.resume()
        _ = try await selection.value
        let results = await [firstRemote.value, secondRemote.value]
        for result in results {
            switch change {
                case .signedOut:
                    guard case .verificationFailed = result else {
                        Issue.record("A remote retry must observe the account failure.")
                        continue
                    }
                case .newerRequirement: #expect(result == .updateRequired(newerVersion))
            }
        }
        #expect(await transport.identityReadCount == identityReads + 1)
        switch change {
            case .signedOut: #expect(await transport.readCount == reads)
            case .newerRequirement: #expect(await transport.readCount == reads + 1)
        }
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await domain.perform {}
        }
    }

    @Test func localHigherFloorWinsWhileRemoteVerificationIsSuspended() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = CompatibilityTestTransport()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: transport,
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let recording = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        _ = try await recording.selectRecordingRole(.recordingRequested)
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            recording: recording,
            installation: installation,
        )
        #expect(await coordinator.recheck() == .compatible(.current))
        let domain = try await coordinator.openDomainStore()
        let gate = CompatibilityTestGate()
        await transport.holdNextRead(gate)
        let remote = Task { await coordinator.recheck() }
        await gate.waitUntilEntered()
        let version = DataCompatibilityVersion(rawValue: 2)
        try await store.perform { try await store.addDataCompatibilityRequirement(.init(
            id: UUID(),
            version: version,
        )) }
        #expect(await coordinator.recheckLocalHistory() == .updateRequired(version))
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await domain.perform {}
        }
        gate.resume()
        #expect(await remote.value == .updateRequired(version))
    }

    @Test func secondaryWaitsForVerificationAfterASufficientFloorArrives() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        _ = try await authority.submit(fixture.proposal(.initial, .claim, device: fixture.phone))
        let installation = RecordingCoordinationInstallation(deviceID: fixture.tablet)
        let recording = RecordingDeviceCoordination(
            supportedVersion: .init(rawValue: 2),
            authority: authority,
            installation: installation,
        )
        _ = try await recording.selectRecordingRole(.secondary)
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            recording: recording,
            installation: installation,
        )
        let owner = try #require(await authority.observed().owner)
        #expect(await coordinator.recheck() == .waitingForRecordingDevice(owner))
        #expect(try await store.requiredDataCompatibilityVersion() == .initial)
        await #expect(throws: DataCompatibilityError.notReady) {
            _ = try await coordinator.openDomainStore()
        }
        // Sync can deliver a sufficient floor, but history observation no longer resumes access.
        let version = DataCompatibilityVersion(rawValue: 2)
        try await store.perform {
            try await store.addDataCompatibilityRequirement(.init(id: UUID(), version: version))
        }
        #expect(await coordinator.recheckLocalHistory() == .waitingForRecordingDevice(owner))
        await #expect(throws: DataCompatibilityError.notReady) {
            _ = try await coordinator.openDomainStore()
        }
        #expect(await coordinator.recheck() == .compatible(version))
        let freshScope = try await coordinator.openDomainStore()
        #expect(try await freshScope.allSamples().isEmpty)
    }

    @Test func ownerAdvancesOnceAndOlderScopesNeverRegainAccess() async throws {
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let oldRecording = RecordingDeviceCoordination(
            supportedVersion: .initial,
            authority: authority,
            installation: installation,
        )
        _ = try await oldRecording.selectRecordingRole(.recordingRequested)
        let old = DataCompatibilityCoordinator(
            store: store,
            recording: oldRecording,
            installation: installation,
        )
        #expect(await old.recheck() == .compatible(.initial))
        let oldScope = try await old.openDomainStore()
        let version = DataCompatibilityVersion(rawValue: 2)
        let newRecording = RecordingDeviceCoordination(
            supportedVersion: version,
            authority: authority,
            installation: installation,
        )
        let updated = DataCompatibilityCoordinator(
            store: store,
            recording: newRecording,
            installation: installation,
        )
        await store.setSupportedDataCompatibilityVersionForTesting(version)
        #expect(await updated.recheck() == .compatible(version))
        let receiptCount = try await store.recordingAuthorityCommits().count
        #expect(await updated.recheck() == .compatible(version))
        #expect(try await store.recordingAuthorityCommits().count == receiptCount)
        #expect(await old.recheck() == .updateRequired(version))
        let newScope = try await updated.openDomainStore()
        #expect(try await newScope.allSamples().isEmpty)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await oldScope.perform {}
        }
    }

    @Test func replacementCanRecoverBeforeAdvancingTheFloor() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        _ = try await authority.submit(claim)
        let installation = RecordingCoordinationInstallation(deviceID: fixture.tablet)
        let recording = RecordingDeviceCoordination(
            supportedVersion: .init(rawValue: 2),
            authority: authority,
            installation: installation,
        )
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            recording: recording,
            installation: installation,
        )
        #expect(await coordinator.recheck() == .recordingChoiceRequired)
        _ = try await recording.recover(replacing: claim.result.owner, history: .keep)
        #expect(try await store.requiredDataCompatibilityVersion() == .initial)
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        #expect(await coordinator.recheck() == .compatible(.init(rawValue: 2)))
        #expect(try await authority.observed().owner?.deviceID == fixture.tablet)
    }

    @Test func offlineUseRetainsTheExistingContractButCannotAdvanceIt() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = CompatibilityTestTransport()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: transport,
            installation: RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID())),
        )
        let installation = RecordingCoordinationInstallation(deviceID: .init(rawValue: UUID()))
        let current = RecordingDeviceCoordination(
            supportedVersion: .initial,
            authority: authority,
            installation: installation,
        )
        _ = try await current.selectRecordingRole(.recordingRequested)
        let established = DataCompatibilityCoordinator(
            store: store,
            recording: current,
            installation: installation,
        )
        #expect(await established.recheck() == .compatible(.initial))
        await transport.setAvailability(.offline)
        #expect(await established.recheck() == .compatible(.initial))
        let updated = DataCompatibilityCoordinator(
            store: store,
            recording: RecordingDeviceCoordination(
                supportedVersion: .init(rawValue: 2),
                authority: authority,
                installation: installation,
            ),
            installation: installation,
        )
        guard case .verificationFailed = await updated.recheck() else {
            Issue.record("An offline owner must not advance the floor.")
            return
        }
        #expect(try await store.requiredDataCompatibilityVersion() == .initial)
        await transport.setAvailability(.signedOut)
        let failed = await established.recheck()
        guard case let .verificationFailed(failure) = failed else {
            Issue.record("Account failures must not authorize cached use.")
            return
        }
        #expect((failure.error as? CKError)?.code == .notAuthenticated)
        #expect(await established.recheckLocalHistory() == failed)
        guard case .verificationFailed = await established.recheckLocalHistory() else {
            Issue.record("Local history must not erase a known account-verification failure.")
            return
        }
    }
}
