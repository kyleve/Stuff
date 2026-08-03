import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 1000)
    private static let initialAssignmentID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    )!
    private static let remoteDeviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    )

    private static func makeServices(
        authorization: LocationAuthorizationStatus = .always,
        initialEnabled: Bool = true,
        remoteChanges: ScriptedStoreRemoteChangeSource? = nil,
    ) throws -> (WhereServices, SwiftDataStore) {
        let store = try if let remoteChanges {
            SwiftDataStore.inMemory(remoteChangeSource: remoteChanges)
        } else {
            SwiftDataStore.inMemory()
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: authorization),
            installationContext: InstallationRecordingContext(
                currentDevice: .preview,
                registeredAt: Self.now,
                initialRecordingChoice: .init(
                    isEnabled: initialEnabled,
                    assignmentChangeID: Self.initialAssignmentID,
                    confirmedAt: Self.now,
                ),
            ),
            now: { Self.now },
        )
        return (services, store)
    }

    private static func addRemoteProfile(to store: SwiftDataStore) async throws {
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: remoteDeviceID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: now,
                registrationEpochID: .initial,
            ))
        }
    }

    @Test func registrationPersistsOneGlobalAssignmentAndAcknowledgesIt() async throws {
        let (services, store) = try Self.makeServices()

        let configuration = try await services.recording.register(authorization: .always)

        #expect(configuration.id == CurrentRecordingDevice.preview.id)
        #expect(configuration.isEnabled == true)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .recording)
        #expect(await services.ingestor.isActive)
        #expect(try await store.recordingDeviceProfiles().count == 1)
        #expect(try await store.recordingAssignmentChanges()
            .map(\.id) == [Self.initialAssignmentID])

        _ = try await services.recording.register(authorization: .always)
        #expect(try await store.recordingAssignmentChanges().count == 1)
    }

    @Test func assignmentWithoutAlwaysPermissionIsAcknowledgedAsPermissionRequired() async throws {
        let (services, _) = try Self.makeServices(authorization: .whenInUse)

        let configuration = try await services.recording.register(authorization: .whenInUse)

        #expect(configuration.isEnabled == true)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .permissionRequired)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func transferMovesTheOnlyAssignmentAndStopsThisDevice() async throws {
        let (services, store) = try Self.makeServices()
        _ = try await services.recording.register(authorization: .always)
        try await Self.addRemoteProfile(to: store)

        let configurations = try await services.recording.setEnabled(
            true,
            for: Self.remoteDeviceID,
        )

        let current = try #require(configurations.first {
            $0.id == CurrentRecordingDevice.preview.id
        })
        let remote = try #require(configurations.first { $0.id == Self.remoteDeviceID })
        #expect(current.isEnabled == false)
        #expect(remote.isEnabled == true)
        #expect(remote.isPending)
        #expect(await services.ingestor.isActive == false)
        #expect(
            try await RecordingAssignmentChange.resolve(store.recordingAssignmentChanges())
                == .resolved(.device(Self.remoteDeviceID)),
        )
    }

    @Test func offClosesRecording() async throws {
        let (services, store) = try Self.makeServices()
        _ = try await services.recording.register(authorization: .always)

        _ = try await services.recording.setEnabled(
            false,
            for: CurrentRecordingDevice.preview.id,
        )

        #expect(await services.ingestor.isActive == false)
        #expect(
            try await RecordingAssignmentChange.resolve(store.recordingAssignmentChanges())
                == .resolved(.off),
        )
    }

    @Test func concurrentDifferentAssignmentsFailClosed() async throws {
        let (services, store) = try Self.makeServices(initialEnabled: false)
        _ = try await services.recording.register(authorization: .always)
        try await Self.addRemoteProfile(to: store)
        let local = RecordingAssignmentChange(
            id: UUID(),
            parentIDs: [Self.initialAssignmentID],
            revision: 1,
            issuedAt: Self.now,
            issuedByDeviceID: CurrentRecordingDevice.preview.id,
            effectiveAt: Self.now,
            assignedDeviceID: CurrentRecordingDevice.preview.id,
            reason: .userCommand,
        )
        let remote = RecordingAssignmentChange(
            id: UUID(),
            parentIDs: [Self.initialAssignmentID],
            revision: 1,
            issuedAt: Self.now,
            issuedByDeviceID: Self.remoteDeviceID,
            effectiveAt: Self.now,
            assignedDeviceID: Self.remoteDeviceID,
            reason: .userCommand,
        )
        try await store.perform {
            try await store.addRecordingAssignmentChange(local)
            try await store.addRecordingAssignmentChange(remote)
        }

        await #expect(throws: RecordingPersistenceError.incompleteAssignmentHistory) {
            try await services.recording.reconcile(authorization: .always)
        }
        #expect(await services.ingestor.isActive == false)
        #expect(try await services.recording.authoritySnapshot().resolution
            == .conflict([CurrentRecordingDevice.preview.id, Self.remoteDeviceID]))
    }

    @Test func archivingTheRecorderAppendsATombstoneAndTurnsRecordingOff() async throws {
        let (services, store) = try Self.makeServices()
        _ = try await services.recording.register(authorization: .always)
        try await Self.addRemoteProfile(to: store)
        _ = try await services.recording.setEnabled(true, for: Self.remoteDeviceID)

        let remaining = try await services.recording.archive(Self.remoteDeviceID)

        #expect(remaining.contains { $0.id == Self.remoteDeviceID } == false)
        #expect(try await store.recordingDeviceArchives().map(\.deviceID) == [Self.remoteDeviceID])
        #expect(
            try await RecordingAssignmentChange.resolve(store.recordingAssignmentChanges())
                == .resolved(.off),
        )
    }
}
