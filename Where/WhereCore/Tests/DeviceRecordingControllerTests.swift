import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func makeController(
        enabled: Bool,
        authorization: LocationAuthorizationStatus = .always,
    ) throws -> (DeviceRecordingController, SwiftDataStore, LocationIngestor) {
        let store = try SwiftDataStore.inMemory()
        let ingestor = LocationIngestor(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: authorization),
            recordingDeviceID: InstallationRecordingContext.testing.currentDevice.id,
            calendar: WhereCoreTestSupport.calendar(),
            outbox: NoOpLocationOutbox(),
            retryQueueCapacity: 1000,
            onPersisted: { _ in },
        )
        let context = InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: Self.now.addingTimeInterval(-100),
            automaticRecordingEnabled: enabled,
            isRejoining: false,
        )
        return (
            DeviceRecordingController(
                store: store,
                ingestor: ingestor,
                installationContext: context,
                now: { Self.now },
                onPolicyChanged: {},
            ),
            store,
            ingestor,
        )
    }

    @Test func registrationAppliesLocalChoiceAndWritesAdvisoryStatus() async throws {
        let (controller, store, ingestor) = try makeController(enabled: true)

        let configuration = try await controller.register(authorization: .always)

        #expect(configuration.localAutomaticRecordingEnabled == true)
        #expect(configuration.device.status == .recording)
        #expect(await ingestor.isActive)
        #expect(try await store.recordingDeviceProfiles().count == 1)
        #expect(try await store.recordingDeviceCheckIns().first?.status == .recording)
    }

    @Test func localSettingsChoiceStopsAndRestartsOnlyThisInstallation() async throws {
        let (controller, _, ingestor) = try makeController(enabled: true)
        _ = try await controller.register(authorization: .always)

        let off = try await controller.setAutomaticRecordingEnabled(
            false,
            authorization: .always,
        )
        #expect(off.localAutomaticRecordingEnabled == false)
        #expect(await ingestor.isActive == false)

        let on = try await controller.setAutomaticRecordingEnabled(
            true,
            authorization: .always,
        )
        #expect(on.localAutomaticRecordingEnabled == true)
        #expect(await ingestor.isActive)
    }

    @Test func removalStopsCurrentIdentityAndPublishesTerminalState() async throws {
        let (controller, store, ingestor) = try makeController(enabled: true)
        _ = try await controller.register(authorization: .always)
        let deviceID = controller.currentDevice.id
        try await store.perform {
            try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: UUID(),
                deviceID: deviceID,
                removedAt: Self.now,
                removedByDeviceID: RecordingDeviceID(rawValue: UUID()),
            ))
        }

        await #expect(throws: RecordingPersistenceError.self) {
            try await controller.reconcile(authorization: .always)
        }

        #expect(await ingestor.isActive == false)
        #expect(await controller.currentRuntimeUpdate()?.state == .removed)
    }

    @Test func remoteRowsNeverExposeALocalPreference() async throws {
        let (controller, store, _) = try makeController(enabled: false)
        _ = try await controller.register(authorization: .always)
        let remoteID = RecordingDeviceID(rawValue: UUID())
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: remoteID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: Self.now,
                registrationEpochID: .initial,
            ))
        }

        let devices = try await controller.devices()

        #expect(devices.first(where: { $0.id == controller.currentDevice.id })?
            .localAutomaticRecordingEnabled == false)
        #expect(devices.first(where: { $0.id == remoteID })?
            .localAutomaticRecordingEnabled == nil)
    }
}
