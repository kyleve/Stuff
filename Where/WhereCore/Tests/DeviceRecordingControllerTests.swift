import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    private struct WaitTimeout: Error {}

    private static let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func makeController(
        enabled: Bool,
        enabledAt: Date? = nil,
        authorization: LocationAuthorizationStatus = .always,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
    ) throws
        -> (DeviceRecordingController, SwiftDataStore, LocationIngestor, ScriptedLocationSource)
    {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: authorization)
        let ingestor = LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: InstallationRecordingContext.testing.currentDevice.id,
            calendar: WhereCoreTestSupport.calendar(),
            outbox: outbox,
            retryQueueCapacity: 1000,
            onPersisted: { _ in },
        )
        let registeredAt = Self.now.addingTimeInterval(-100)
        let context = InstallationRecordingContext(
            currentDevice: InstallationRecordingContext.testing.currentDevice,
            registeredAt: registeredAt,
            recordingChoice: enabled ? .on(enabledAt: enabledAt ?? registeredAt) : .off,
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
            source,
        )
    }

    @Test func registrationAppliesLocalChoiceAndWritesAdvisoryStatus() async throws {
        let (controller, store, ingestor, _) = try makeController(enabled: true)

        let configuration = try await controller.register(authorization: .always)

        #expect(configuration.localAutomaticRecordingEnabled == true)
        #expect(configuration.device.status == .recording)
        #expect(await ingestor.isActive)
        #expect(try await store.recordingDeviceProfiles().count == 1)
        #expect(try await store.recordingDeviceCheckIns().first?.status == .recording)
    }

    @Test func registrationRestoresTheLatestEnableCutoff() async throws {
        let enabledAt = Self.now.addingTimeInterval(-50)
        let (controller, store, _, source) = try makeController(
            enabled: true,
            enabledAt: enabledAt,
        )
        _ = try await controller.register(authorization: .always)
        let beforeEnable = LocationSample(
            timestamp: enabledAt.addingTimeInterval(-1),
            coordinate: Coordinate(latitude: 37, longitude: -122),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        )
        let afterEnable = LocationSample(
            timestamp: enabledAt.addingTimeInterval(1),
            coordinate: Coordinate(latitude: 37, longitude: -122),
            horizontalAccuracy: 0,
            source: .gpsVisit,
        )

        source.emit(beforeEnable)
        source.emit(afterEnable)

        try await waitUntil {
            await (try? store.allSamples().count) == 1
        }
        #expect(try await store.allSamples().map(\.id) == [afterEnable.id])
    }

    private func waitUntil(
        _ predicate: () async -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await predicate() == false {
            guard ContinuousClock.now < deadline else { throw WaitTimeout() }
            await Task.yield()
        }
    }

    @Test func localSettingsChoiceStopsAndRestartsOnlyThisInstallation() async throws {
        let (controller, _, ingestor, _) = try makeController(enabled: true)
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

    @Test func failedOffCleanupPublishesUnavailableAndBlocksReenable() async throws {
        let outbox = ScriptedLocationOutbox()
        let (controller, _, ingestor, _) = try makeController(
            enabled: true,
            outbox: outbox,
        )
        _ = try await controller.register(authorization: .always)
        await outbox.setFailsToClear(true)

        await #expect(throws: (any Error).self) {
            try await controller.setAutomaticRecordingEnabled(false, authorization: .always)
        }
        #expect(await controller.currentRuntimeUpdate()?.state == .unavailable)
        #expect(await ingestor.isActive == false)

        await #expect(throws: (any Error).self) {
            try await controller.setAutomaticRecordingEnabled(true, authorization: .always)
        }
        #expect(await ingestor.isActive == false)

        await outbox.setFailsToClear(false)
        let recovered = try await controller.setAutomaticRecordingEnabled(
            true,
            authorization: .always,
        )
        #expect(recovered.localAutomaticRecordingEnabled == true)
        #expect(await ingestor.isActive)
    }

    @Test func removalStopsCurrentIdentityAndPublishesTerminalState() async throws {
        let (controller, store, ingestor, _) = try makeController(enabled: true)
        _ = try await controller.register(authorization: .always)
        let deviceID = controller.currentDevice.id
        try await store.perform {
            try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: .init(rawValue: UUID()),
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
        let (controller, store, _, _) = try makeController(enabled: false)
        _ = try await controller.register(authorization: .always)
        let remoteID = RecordingDeviceID(rawValue: UUID())
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: remoteID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: Self.now,
                registrationGenerationID: .initial,
            ))
        }

        let devices = try await controller.devices()

        #expect(devices.first(where: { $0.id == controller.currentDevice.id })?
            .localAutomaticRecordingEnabled == false)
        #expect(devices.first(where: { $0.id == remoteID })?
            .localAutomaticRecordingEnabled == nil)
    }
}
