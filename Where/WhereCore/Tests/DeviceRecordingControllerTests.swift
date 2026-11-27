import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    @Test func committedImportCannotResumeRetiredRecording() async throws {
        let (controller, _, ingestor, _) = try makeController(enabled: true)
        _ = try await controller.register(authorization: .always)
        await controller.shutdown()
        await #expect(throws: CancellationError.self) {
            try await controller.resumeAfterImport(discardPendingSamples: false)
        }
        await controller.resumeAfterImportRollback()
        #expect(await !ingestor.isActive)
    }

    private struct WaitTimeout: Error {}

    private static let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func makeController(
        enabled: Bool,
        enabledAt: Date? = nil,
        authorization: LocationAuthorizationStatus = .always,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
        updateShareAuthor: @escaping @Sendable (WhereDataGenerationID?) async throws
            -> Void = { _ in
            },
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
                updateShareAuthor: updateShareAuthor,
                now: { Self.now },
                onPolicyChanged: {},
            ),
            store,
            ingestor,
            source,
        )
    }

    @Test func recordingOffPublishesShareAuthorAndImportRevokesItUntilRecovery() async throws {
        let updates = ShareAuthorityUpdates()
        let (controller, store, _, _) = try makeController(
            enabled: false,
            authorization: .denied,
            updateShareAuthor: { await updates.record($0) },
        )
        _ = try await controller.register(authorization: .denied)
        #expect(await updates.values == [.initial])
        try await controller.pause()
        #expect(await updates.values.last == .some(nil))
        await controller.resumeAfterImportRollback()
        #expect(await updates.values.last == .some(.initial))
        try await controller.pause()
        let next = try await store.perform {
            try await store.rotateDataGeneration(
                reason: .backupReplace,
                changedBy: controller.currentDevice.id,
                at: Self.now,
            )
        }
        try await controller.resumeAfterImport(discardPendingSamples: true)
        #expect(await updates.values.last == .some(next.id))
        try await controller.retireForRejoin()
        #expect(await updates.values.last == .some(nil))
    }

    @Test func historicalNamesSurviveRemovalAndUseTheLatestNickname() async throws {
        let (controller, store, _, _) = try makeController(enabled: false)
        _ = try await controller.register(authorization: .always)
        let remoteID = RecordingDeviceID(rawValue: UUID())
        let profile = RecordingDeviceProfile(
            id: remoteID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: Self.now,
            registrationGenerationID: .initial,
        )
        try await store.perform { try await store.addRecordingDeviceProfile(profile) }
        #expect(try await controller.displayNames()[remoteID] == nil)
        try await store.perform {
            try await store.addRecordingDeviceMetadataChange(.hardwareModelIdentifier(
                "iPad99,1",
                for: profile,
            ))
        }
        #expect(try await controller.displayNames()[remoteID] == "iPad99,1")
        _ = try await controller.rename(remoteID, to: "Old tablet")
        _ = try await controller.rename(remoteID, to: "Travel tablet")
        #expect(try await controller.displayNames()[remoteID] == "Travel tablet")
        _ = try await controller.rename(remoteID, to: "  ")
        #expect(try await controller.displayNames()[remoteID] == "iPad99,1")
        _ = try await controller.rename(remoteID, to: "Travel tablet")

        _ = try await controller.remove(remoteID)

        #expect(try await controller.displayNames()[remoteID] == "Travel tablet")
        #expect(try await controller.devices().contains { $0.id == remoteID } == false)
        #expect(try await controller.displayNames()[RecordingDeviceID(rawValue: UUID())] == nil)
    }

    @Test func registeringAConfirmedInstallationReplaysItsNicknameWithoutOverridingALaterRename(
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        let device = CurrentRecordingDevice.preview
        let context = InstallationRecordingContext(
            currentDevice: device,
            registeredAt: Self.now,
            recordingChoice: .unconfirmed,
            isRejoining: false,
        ).confirmingInitialRecording(isEnabled: false, name: " Travel Phone ")
        let pending = try #require(context.pendingInitialNickname)
        let existingProfile = RecordingDeviceProfile(
            id: device.id,
            systemName: "iPhone",
            kind: .phone,
            registeredAt: Self.now,
            registrationGenerationID: .initial,
        )
        try await store.perform { try await store.addRecordingDeviceProfile(existingProfile) }
        let first = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            installationContext: context,
            acknowledgeInitialNickname: { _, _ in throw WaitTimeout() },
        )
        await #expect(throws: WaitTimeout.self) {
            try await first.recording.register(authorization: .denied)
        }
        let initial = try await store.recordingDeviceMetadataChanges()
        #expect(initial.count == 2)
        #expect(initial.first { $0.id == pending.id }?.nickname == "Travel Phone")
        _ = try await first.recording.rename(device.id, to: "Renamed")
        let beforeReplay = try await store.recordingDeviceMetadataChanges()
        let relaunched = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            installationContext: context,
            acknowledgeInitialNickname: { id, event in
                #expect(id == device.id)
                #expect(event == pending.id)
            },
        )
        let configuration = try await relaunched.recording.register(authorization: .denied)
        #expect(configuration.device.displayName == "Renamed")
        #expect(configuration.device.modelName == "iPhone 15 Pro")
        #expect(configuration.device.status == .off)
        #expect(try await store.recordingDeviceMetadataChanges() == beforeReplay)
        #expect(try await store.recordingDeviceProfiles() == [existingProfile])
        _ = try await relaunched.recording.rename(device.id, to: "  iPhone 15 Pro  ")
        #expect(try await relaunched.recording.displayNames()[device.id] == "iPhone 15 Pro")
    }

    @Test func registrationRejectsAReusedInstallationIDWithoutPublishingMetadata() async throws {
        let store = try SwiftDataStore.inMemory()
        let device = CurrentRecordingDevice.preview
        let context = InstallationRecordingContext(
            currentDevice: device,
            registeredAt: Self.now,
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        .confirmingInitialRecording(isEnabled: false, name: "New name")
        let conflictingProfile = RecordingDeviceProfile(
            id: device.id,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: Self.now,
            registrationGenerationID: .initial,
        )
        try await store.perform { try await store.addRecordingDeviceProfile(conflictingProfile) }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            installationContext: context,
        )
        await #expect(throws: RecordingPersistenceError
            .conflictingImmutableRecord(id: device.id.rawValue))
        {
            try await services.recording.register(authorization: .denied)
        }
        #expect(try await store.recordingDeviceProfiles() == [conflictingProfile])
        #expect(try await store.recordingDeviceMetadataChanges().isEmpty)
    }

    @Test func removalBeforeProfileDeliveryPreventsPublishingModelOrInitialName() async throws {
        let store = try SwiftDataStore.inMemory()
        let device = CurrentRecordingDevice.preview
        let context = InstallationRecordingContext(
            currentDevice: device,
            registeredAt: Self.now,
            recordingChoice: .unconfirmed,
            isRejoining: false,
        )
        .confirmingInitialRecording(isEnabled: false, name: "Retired")
        try await store.perform {
            try await store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: device.id,
                removedAt: Self.now,
                removedByDeviceID: .init(rawValue: UUID()),
            ))
        }
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            installationContext: context,
            acknowledgeInitialNickname: { _, _ in
                Issue.record("Retired installation acknowledged its name")
            },
        )
        await #expect(throws: RecordingPersistenceError.currentDeviceRemoved(device.id)) {
            try await services.recording.register(authorization: .denied)
        }
        #expect(try await store.recordingDeviceProfiles().isEmpty)
        #expect(try await store.recordingDeviceMetadataChanges().isEmpty)
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

private actor ShareAuthorityUpdates {
    private(set) var values: [WhereDataGenerationID?] = []
    func record(_ value: WhereDataGenerationID?) {
        values.append(value)
    }
}
