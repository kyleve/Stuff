import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct DataCompatibilityCoordinatorTests {
    @Test func secondaryUpdatingFirstWaitsWithoutRaisingTheFloor() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
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
        // The current build still reads the unchanged shared contract.
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func ownerAdvancesOnceAndOlderScopesNeverRegainAccess() async throws {
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
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
            _ = try await oldScope.allSamples()
        }
    }

    @Test func replacementCanRecoverBeforeAdvancingTheFloor() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
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
        _ = try await recording.recover(replacing: #require(claim.result.owner), history: .keep)
        #expect(try await store.requiredDataCompatibilityVersion() == .initial)
        await store.setSupportedDataCompatibilityVersionForTesting(.init(rawValue: 2))
        #expect(await coordinator.recheck() == .compatible(.init(rawValue: 2)))
        #expect(try await authority.observed().owner?.deviceID == fixture.tablet)
    }

    @Test func offlineUseRetainsTheExistingContractButCannotAdvanceIt() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = CompatibilityTestTransport()
        let authority = RecordingAuthorityCoordinator(store: store, transport: transport)
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
        guard case .verificationFailed = await established.recheck() else {
            Issue.record("Account failures must not authorize cached use.")
            return
        }
    }
}
