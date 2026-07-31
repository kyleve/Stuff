import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    private static let now = WhereCoreTestSupport.iso("2026-07-30T12:00:00-07:00")

    private static func makeServices(
        authorization: LocationAuthorizationStatus,
    ) throws -> (WhereServices, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: authorization),
            recordingParticipation: .recording(
                device: .preview,
                defaultEnabledForNewInstallation: true,
            ),
            now: { now },
        )
        return (services, store)
    }

    @Test func firstReconcileRegistersMigratedIntentAndAcknowledgesRecording() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)

        let configuration = try #require(try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .always,
        ))

        #expect(configuration.id == CurrentRecordingDevice.preview.id)
        #expect(configuration.isEnabled)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .recording)
        #expect(await services.ingestor.isActive)
        #expect(try await store.recordingDevices().count == 1)
        #expect(try await store.recordingPolicyChanges().count == 1)
    }

    @Test func enabledWithoutAlwaysPermissionIsAcknowledgedAsPermissionRequired() async throws {
        let (services, _) = try Self.makeServices(authorization: .whenInUse)

        let configuration = try #require(try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .whenInUse,
        ))

        #expect(configuration.isEnabled)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .permissionRequired)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func rapidChangesWithTheSameClockValueKeepInvocationOrder() async throws {
        let (services, _) = try Self.makeServices(authorization: .always)
        _ = try await services.recording.setEnabled(
            true,
            for: CurrentRecordingDevice.preview.id,
            initialEnabled: false,
        )
        let devices = try await services.recording.setEnabled(
            false,
            for: CurrentRecordingDevice.preview.id,
            initialEnabled: false,
        )
        let current = try #require(
            devices.first(where: { $0.id == CurrentRecordingDevice.preview.id }),
        )

        #expect(current.isEnabled == false)
        #expect(current.device.status == .off)
        #expect(current.isPending == false)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func remoteDisableIsPendingUntilThatDeviceAcknowledges() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .always,
        )
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        let initialPolicyID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: remoteID,
                systemName: "iPad",
                nickname: "Travel iPad",
                kind: .tablet,
                registeredAt: Self.now,
                lastSeenAt: Self.now,
                archivedAt: nil,
                lastAppliedPolicyChangeID: initialPolicyID,
                status: .recording,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: initialPolicyID,
                deviceID: remoteID,
                effectiveAt: Self.now.addingTimeInterval(-60),
                isEnabled: true,
            ))
        }

        let devices = try await services.recording.setEnabled(
            false,
            for: remoteID,
            initialEnabled: true,
        )
        let remote = try #require(devices.first(where: { $0.id == remoteID }))

        #expect(remote.isEnabled == false)
        #expect(remote.isPending)
        #expect(remote.device.status == .recording)
    }

    @Test func archivingTurnsRemoteDeviceOffAndHidesItAtomically() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .always,
        )
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: remoteID,
                systemName: "iPad",
                nickname: nil,
                kind: .tablet,
                registeredAt: Self.now,
                lastSeenAt: Self.now,
                archivedAt: nil,
                lastAppliedPolicyChangeID: nil,
                status: .off,
            ))
        }

        let visible = try await services.recording.archive(
            remoteID,
            initialEnabled: true,
        )

        #expect(visible.contains(where: { $0.id == remoteID }) == false)
        let archived = try #require(
            try await store.recordingDevices().first(where: { $0.id == remoteID }),
        )
        #expect(archived.archivedAt == Self.now)
        let latest = try #require(
            try await store.recordingPolicyChanges().last(where: { $0.deviceID == remoteID }),
        )
        #expect(latest.isEnabled == false)
    }

    @Test func archivedCurrentDeviceCanSeeItselfAndReenable() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        let policyID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: CurrentRecordingDevice.preview.id,
                systemName: "iPhone",
                nickname: nil,
                kind: .phone,
                registeredAt: Self.now,
                lastSeenAt: Self.now,
                archivedAt: Self.now,
                lastAppliedPolicyChangeID: policyID,
                status: .off,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: policyID,
                deviceID: CurrentRecordingDevice.preview.id,
                effectiveAt: Self.now,
                isEnabled: false,
            ))
        }

        let before = try await services.recording.devices(initialEnabled: false)
        #expect(before.map(\.id) == [CurrentRecordingDevice.preview.id])

        let after = try await services.recording.setEnabled(
            true,
            for: CurrentRecordingDevice.preview.id,
            initialEnabled: false,
        )
        let current = try #require(after.first)
        #expect(current.isEnabled)
        #expect(current.device.archivedAt == nil)
        #expect(current.device.status == .recording)
    }

    @Test func quiescedControllerCannotRecreateRowsAfterReset() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .always,
        )

        await services.recording.quiesce()
        try await store.perform { try await store.clearAll() }

        await #expect(throws: CancellationError.self) {
            _ = try await services.recording.devices(initialEnabled: true)
        }
        #expect(try await store.recordingDevices().isEmpty)
        #expect(try await store.recordingPolicyChanges().isEmpty)
    }

    @Test func managementOnlyReconcileNeverRegistersOrStartsLocalRecording() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let services = WhereServices(
            store: store,
            locationSource: source,
            recordingParticipation: .managementOnly,
            now: { Self.now },
        )

        let configuration = try await services.recording.reconcile(
            initialEnabled: true,
            authorization: .always,
        )
        await services.ingestor.start()
        await services.ingestor.captureTodayIfNeeded(now: Self.now)

        #expect(configuration == nil)
        #expect(await services.ingestor.isActive == false)
        #expect(try await store.recordingDevices().isEmpty)
        #expect(try await store.recordingPolicyChanges().isEmpty)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func managementOnlyControllerCanManageASyncedRemoteDevice() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: IdleLocationSource(),
            recordingParticipation: .managementOnly,
            now: { Self.now },
        )
        let remoteID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
        )
        try await store.perform {
            try await store.setRecordingDevice(RecordingDevice(
                id: remoteID,
                systemName: "iPad",
                nickname: nil,
                kind: .tablet,
                registeredAt: Self.now,
                lastSeenAt: Self.now,
                archivedAt: nil,
                lastAppliedPolicyChangeID: nil,
                status: .off,
            ))
        }

        let before = try await services.recording.devices(initialEnabled: false)
        let after = try await services.recording.setEnabled(
            true,
            for: remoteID,
            initialEnabled: false,
        )

        #expect(before.map(\.id) == [remoteID])
        #expect(after.map(\.id) == [remoteID])
        #expect(after.first?.isEnabled == true)
        #expect(try await store.recordingDevices().count == 1)
    }
}
