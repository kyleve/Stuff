import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct DeviceRecordingControllerTests {
    private static let now = WhereCoreTestSupport.iso("2026-07-30T12:00:00-07:00")
    private static let initialPolicyID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
    )!
    private static let remoteDeviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    )
    private static let remotePolicyID = UUID(
        uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
    )!
    private static func makeServices(
        authorization: LocationAuthorizationStatus,
        initialEnabled: Bool = true,
        now: @escaping @Sendable () -> Date = { Self.now },
        remoteChanges: ScriptedStoreRemoteChangeSource? = nil,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
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
                    policyChangeID: initialPolicyID,
                    confirmedAt: Self.now,
                ),
            ),
            locationOutbox: outbox,
            now: now,
        )
        return (services, store)
    }

    private static func register(
        _ services: WhereServices,
        authorization: LocationAuthorizationStatus = .always,
    ) async throws -> RecordingDeviceConfiguration {
        try await services.recording.register(authorization: authorization)
    }

    private static func pendingSample(
        at timestamp: Date = Self.now.addingTimeInterval(-30),
    ) -> LocationSample {
        LocationSample(
            timestamp: timestamp,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsVisit,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
        )
    }

    private static func seedRemoteDevice(
        in store: SwiftDataStore,
        nickname: String? = "Travel iPad",
        status: RecordingDeviceStatus = .recording,
    ) async throws {
        let profile = RecordingDeviceProfile(
            id: remoteDeviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: now,
            registrationEpochID: .initial,
        )
        let policy = RecordingPolicyChange(
            id: remotePolicyID,
            deviceID: remoteDeviceID,
            parentIDs: [],
            revision: 0,
            issuedAt: now.addingTimeInterval(-60),
            issuedByDeviceID: remoteDeviceID,
            effectiveAt: now.addingTimeInterval(-60),
            state: status == .recording ? .on : .off,
            reason: .initialRegistration,
        )
        let metadata = RecordingDeviceMetadataChange(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            deviceID: remoteDeviceID,
            revision: 0,
            changedAt: now,
            changedByDeviceID: remoteDeviceID,
            nickname: nickname,
        )
        let checkIn = RecordingDeviceCheckIn(
            deviceID: remoteDeviceID,
            revision: 0,
            lastSeenAt: now,
            appliedAt: now,
            lastAppliedPolicyChangeID: remotePolicyID,
            status: status,
        )
        try await store.perform {
            try await store.addRecordingDeviceProfile(profile)
            try await store.addRecordingDeviceMetadataChange(metadata)
            try await store.addRecordingPolicyChange(policy)
            try await store.setRecordingDeviceCheckIn(checkIn)
        }
    }

    @Test func explicitRegistrationPersistsIdentityPolicyAndAcknowledgement() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)

        let configuration = try await Self.register(services)

        #expect(configuration.id == CurrentRecordingDevice.preview.id)
        #expect(configuration.isEnabled == true)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .recording)
        #expect(await services.ingestor.isActive)
        #expect(try await store.recordingDeviceProfiles().count == 1)
        #expect(try await store.recordingDeviceCheckIns().count == 1)
        #expect(try await store.recordingPolicyChanges().map(\.id) == [Self.initialPolicyID])

        _ = try await Self.register(services)
        #expect(try await store.recordingDeviceProfiles().count == 1)
        #expect(try await store.recordingPolicyChanges().count == 1)
    }

    @Test func registrationInDestructiveEpochRejectsABufferedPreEraseFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let erasedAt = Self.now.addingTimeInterval(60)
        let epoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: Self.remoteDeviceID,
                at: erasedAt,
            )
        }
        let services = WhereServices(
            store: store,
            locationSource: source,
            installationContext: InstallationRecordingContext(
                currentDevice: .preview,
                registeredAt: Self.now,
                initialRecordingChoice: .init(
                    isEnabled: true,
                    policyChangeID: Self.initialPolicyID,
                    confirmedAt: Self.now,
                ),
            ),
            now: { erasedAt },
        )
        let bufferedBeforeErase = Self.pendingSample(
            at: erasedAt.addingTimeInterval(-1),
        )
        let afterErase = Self.pendingSample(
            at: erasedAt.addingTimeInterval(1),
        )

        source.emit(bufferedBeforeErase)
        let configuration = try await Self.register(services)

        #expect(configuration.isEnabled == true)
        #expect(await services.ingestor.isActive)
        let initialPolicy = try #require(try await store.recordingPolicyChanges().first)
        #expect(initialPolicy.effectiveAt == epoch.changedAt)
        try await waitUntil {
            await services.ingestor.testingHasConsumedSample(id: bufferedBeforeErase.id)
        }
        #expect(try await store.allSamples().isEmpty)

        source.emit(afterErase)
        try await waitUntil { await (try? store.allSamples().count) == 1 }
        #expect(try await store.allSamples().map(\.id) == [afterErase.id])
    }

    @Test func enabledWithoutAlwaysPermissionIsAcknowledgedAsPermissionRequired() async throws {
        let (services, _) = try Self.makeServices(authorization: .whenInUse)

        let configuration = try await Self.register(
            services,
            authorization: .whenInUse,
        )

        #expect(configuration.isEnabled == true)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .permissionRequired)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func rapidChangesWithTheSameClockValueKeepInvocationOrder() async throws {
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
        )
        _ = try await Self.register(services)

        _ = try await services.recording.setEnabled(
            true,
            for: CurrentRecordingDevice.preview.id,
        )
        let devices = try await services.recording.setEnabled(
            false,
            for: CurrentRecordingDevice.preview.id,
        )
        let current = try #require(
            devices.first(where: { $0.id == CurrentRecordingDevice.preview.id }),
        )

        #expect(current.isEnabled == false)
        #expect(current.device.status == .off)
        #expect(current.isPending == false)
        #expect(await services.ingestor.isActive == false)
        let policies = try await store.recordingPolicyChanges()
            .filter { $0.deviceID == CurrentRecordingDevice.preview.id }
        #expect(policies.map(\.revision) == [0, 1, 2])
        #expect(Set(policies.map(\.effectiveAt)) == Set([Self.now]))
    }

    @Test func localOffClosesIngestionBeforeDerivedDataFanoutFinishes() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor = LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
            calendar: WhereCoreTestSupport.calendar(),
            onPersisted: { _ in },
        )
        let (fanoutStarted, fanoutStartedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (releaseFanout, releaseFanoutContinuation) = AsyncStream.makeStream(of: Void.self)
        let controller = DeviceRecordingController(
            store: store,
            ingestor: ingestor,
            installationContext: InstallationRecordingContext(
                currentDevice: .preview,
                registeredAt: Self.now,
                initialRecordingChoice: .init(
                    isEnabled: true,
                    policyChangeID: Self.initialPolicyID,
                    confirmedAt: Self.now,
                ),
            ),
            now: { Self.now },
            onPolicyChanged: {
                fanoutStartedContinuation.yield()
                fanoutStartedContinuation.finish()
                for await _ in releaseFanout {
                    break
                }
            },
        )
        _ = try await controller.register(authorization: .always)
        #expect(await ingestor.isActive)

        let command = Task {
            try await controller.setEnabled(
                false,
                for: CurrentRecordingDevice.preview.id,
            )
        }
        var fanoutIterator = fanoutStarted.makeAsyncIterator()
        _ = await fanoutIterator.next()

        #expect(await ingestor.isActive == false)
        releaseFanoutContinuation.yield()
        releaseFanoutContinuation.finish()
        _ = try await command.value
    }

    @Test func unreadableRetryBacklogLeavesOnPolicyUnacknowledgedAndClosed() async throws {
        let outbox = ScriptedLocationOutbox(failsToLoad: true)
        let (services, store) = try Self.makeServices(
            authorization: .always,
            outbox: outbox,
        )

        await #expect(throws: ScriptedLocationOutbox.Failure.self) {
            try await Self.register(services)
        }

        #expect(await services.ingestor.isActive == false)
        #expect(try await store.recordingDeviceCheckIns().isEmpty)

        await outbox.setFailsToLoad(false)
        let configuration = try await Self.register(services)
        #expect(configuration.device.status == .recording)
        #expect(configuration.isPending == false)
        #expect(await services.ingestor.isActive)
    }

    @Test func onboardingRetryPreservesInitialEventAndAppliesTheCurrentSelection() async throws {
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: true,
        )

        let configuration = try await services.recording.registerForOnboarding(
            desiredEnabled: false,
            authorization: .always,
        )

        #expect(configuration.isEnabled == false)
        #expect(configuration.device.status == .off)
        #expect(await services.ingestor.isActive == false)
        let policies = try await store.recordingPolicyChanges()
        #expect(policies.map(\.id).contains(Self.initialPolicyID))
        #expect(policies.map(\.isEnabled) == [true, false])
        #expect(policies.map(\.revision) == [0, 1])
    }

    @Test func profileWithoutPolicyRendersUnknownInsteadOfInventingEnabled() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: Self.remoteDeviceID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: Self.now,
                registrationEpochID: .initial,
            ))
        }

        let remote = try #require(
            try await services.recording.devices().first(where: {
                $0.id == Self.remoteDeviceID
            }),
        )

        #expect(remote.policy == .unknown)
        #expect(remote.isEnabled == nil)
        #expect(remote.isPending)
        #expect(remote.device.status == .unknown)
    }

    @Test func remoteDisableIsPendingUntilThatDeviceAcknowledges() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)
        try await Self.seedRemoteDevice(in: store)

        let devices = try await services.recording.setEnabled(false, for: Self.remoteDeviceID)
        let remote = try #require(devices.first(where: { $0.id == Self.remoteDeviceID }))

        #expect(remote.isEnabled == false)
        #expect(remote.isPending)
        #expect(remote.device.status == .recording)
        #expect(remote.device.nickname == "Travel iPad")
    }

    @Test func targetDeviceCheckInAcknowledgesRemoteDisableAndClearsPending() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)
        try await Self.seedRemoteDevice(in: store)

        let pendingDevices = try await services.recording.setEnabled(
            false,
            for: Self.remoteDeviceID,
        )
        let pending = try #require(
            pendingDevices.first(where: { $0.id == Self.remoteDeviceID }),
        )
        let disableID = try #require(pending.latestPolicyChangeID)
        #expect(pending.isPending)
        #expect(pending.device.status == .recording)

        try await store.simulateRemoteRecordingImport(
            profiles: [],
            metadataChanges: [],
            checkIns: [RecordingDeviceCheckIn(
                deviceID: Self.remoteDeviceID,
                revision: 1,
                lastSeenAt: Self.now.addingTimeInterval(60),
                appliedAt: Self.now.addingTimeInterval(60),
                lastAppliedPolicyChangeID: disableID,
                status: .off,
            )],
            policyChanges: [],
        )

        let acknowledged = try #require(
            try await services.recording.devices().first(where: {
                $0.id == Self.remoteDeviceID
            }),
        )
        #expect(acknowledged.isEnabled == false)
        #expect(acknowledged.isPending == false)
        #expect(acknowledged.device.status == .off)
        #expect(acknowledged.latestPolicyChangeID == disableID)
    }

    @Test func archivingTurnsRemoteDeviceOffAndHidesItAtomically() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)
        try await Self.seedRemoteDevice(in: store, nickname: nil, status: .off)

        let visible = try await services.recording.archive(Self.remoteDeviceID)

        #expect(visible.contains(where: { $0.id == Self.remoteDeviceID }) == false)
        let archived = try #require(
            try await store.recordingDevices().first(where: { $0.id == Self.remoteDeviceID }),
        )
        #expect(archived.archivedAt == Self.now)
        let latest = try #require(
            try await store.recordingPolicyChanges()
                .filter { $0.deviceID == Self.remoteDeviceID }
                .max(by: RecordingPolicyChange.isOrderedBefore),
        )
        #expect(latest.isEnabled == false)
    }

    @Test func remotelyArchivedCurrentDeviceCanSeeItselfAndReenable() async throws {
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
        )
        _ = try await Self.register(services)
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .archived,
                reason: .archive,
            ))
        }

        let before = try await services.recording.devices()
        #expect(before.map(\.id) == [CurrentRecordingDevice.preview.id])

        let after = try await services.recording.setEnabled(
            true,
            for: CurrentRecordingDevice.preview.id,
        )
        let current = try #require(after.first)
        #expect(current.isEnabled == true)
        #expect(current.device.archivedAt == nil)
        #expect(current.device.status == .recording)
    }

    @Test func remotePolicyNotificationStopsTheTargetAndAcknowledgesIt() async throws {
        let remoteChanges = ScriptedStoreRemoteChangeSource()
        let (services, store) = try Self.makeServices(
            authorization: .always,
            remoteChanges: remoteChanges,
        )
        _ = try await Self.register(services)
        await services.recording.startMonitoringPolicyChanges()
        let disableID = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))

        try await store.simulateRemoteRecordingImport(
            profiles: [],
            metadataChanges: [],
            checkIns: [],
            policyChanges: [RecordingPolicyChange(
                id: disableID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now.addingTimeInterval(60),
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now.addingTimeInterval(60),
                state: .off,
                reason: .userCommand,
            )],
        )
        remoteChanges.yield()

        try await waitUntil {
            let checkIn = try? await store.recordingDeviceCheckIns().first
            return checkIn?.lastAppliedPolicyChangeID == disableID
        }
        #expect(await services.ingestor.isActive == false)
        let configuration = try #require(
            try await services.recording.devices().first(where: {
                $0.id == CurrentRecordingDevice.preview.id
            }),
        )
        #expect(configuration.isEnabled == false)
        #expect(configuration.isPending == false)
        #expect(configuration.device.status == .off)
    }

    @Test func remoteArchivedAuthorityStopsTheTargetAndAcknowledgesIt() async throws {
        let remoteChanges = ScriptedStoreRemoteChangeSource()
        let (services, store) = try Self.makeServices(
            authorization: .always,
            remoteChanges: remoteChanges,
        )
        _ = try await Self.register(services)
        await services.recording.startMonitoringPolicyChanges()
        let archiveID = try #require(
            UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB"),
        )

        try await store.simulateRemoteRecordingImport(
            profiles: [],
            metadataChanges: [],
            checkIns: [],
            policyChanges: [RecordingPolicyChange(
                id: archiveID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now.addingTimeInterval(60),
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now.addingTimeInterval(60),
                state: .archived,
                reason: .archive,
            )],
        )
        remoteChanges.yield()

        try await waitUntil {
            let checkIn = try? await store.recordingDeviceCheckIns().first
            return checkIn?.lastAppliedPolicyChangeID == archiveID && checkIn?.status == .off
        }
        #expect(await services.ingestor.isActive == false)
        let current = try #require(try await services.recording.devices().first)
        #expect(current.id == CurrentRecordingDevice.preview.id)
        #expect(current.isArchived)
        #expect(current.device.status == .off)
    }

    @Test func destructivePolicyClearsTheBacklogBeforeAcknowledgement() async throws {
        let pending = Self.pendingSample()
        let outbox = ScriptedLocationOutbox([pending])
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
            outbox: outbox,
        )
        _ = try await Self.register(services)
        let barrierID = UUID()
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: barrierID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .off,
                reason: .backupReplace,
            ))
        }

        _ = try await services.recording.reconcile(authorization: .always)

        #expect(await outbox.persistedSamples.isEmpty)
        let checkIn = try #require(try await store.recordingDeviceCheckIns().first)
        #expect(checkIn.lastAppliedPolicyChangeID == barrierID)
        #expect(checkIn.lastDiscardedPolicyChangeID == barrierID)
        #expect(checkIn.revision == 1)
    }

    @Test func destructiveCleanupFailureLeavesTheBarrierUnacknowledgedAndOff() async throws {
        let pending = Self.pendingSample()
        let outbox = ScriptedLocationOutbox([pending], failsToClear: true)
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
            outbox: outbox,
        )
        _ = try await Self.register(services)
        let initialCheckIn = try #require(try await store.recordingDeviceCheckIns().first)
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: UUID(),
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .off,
                reason: .backupReplace,
            ))
        }

        await #expect(throws: ScriptedLocationOutbox.Failure.self) {
            try await services.recording.reconcile(authorization: .always)
        }

        #expect(await outbox.persistedSamples == [pending])
        #expect(try await store.recordingDeviceCheckIns().first == initialCheckIn)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func laterOnStillClearsAnInterveningDestructiveBarrier() async throws {
        let pending = Self.pendingSample()
        let outbox = ScriptedLocationOutbox([pending])
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
            outbox: outbox,
        )
        _ = try await Self.register(services)
        let barrierID = UUID()
        let onID = UUID()
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: barrierID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .off,
                reason: .backupReplace,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: onID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [barrierID],
                revision: 2,
                issuedAt: Self.now.addingTimeInterval(1),
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now.addingTimeInterval(1),
                state: .on,
                reason: .userCommand,
            ))
        }

        let configuration = try await services.recording.reconcile(authorization: .always)

        #expect(configuration.isEnabled == true)
        #expect(await services.ingestor.isActive)
        #expect(await outbox.persistedSamples.isEmpty)
        let checkIn = try #require(try await store.recordingDeviceCheckIns().first)
        #expect(checkIn.lastAppliedPolicyChangeID == onID)
        #expect(checkIn.lastDiscardedPolicyChangeID == barrierID)
    }

    @Test func destructiveEventOnLosingBranchStillClearsTheBacklog() async throws {
        let pending = Self.pendingSample()
        let outbox = ScriptedLocationOutbox([pending])
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
            outbox: outbox,
        )
        _ = try await Self.register(services)
        let losingOffID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let archiveID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000"))
        let barrierID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000000"))
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: losingOffID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .off,
                reason: .userCommand,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: archiveID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 1,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .archived,
                reason: .archive,
            ))
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: barrierID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [losingOffID],
                revision: 2,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .off,
                reason: .backupReplace,
            ))
        }

        let configuration = try await services.recording.reconcile(authorization: .always)

        // The destructive descendant remains a maximal head even though its parent lost the
        // prior tie. Destructive safety outranks the concurrent archive state.
        #expect(configuration.latestPolicyChangeID == barrierID)
        #expect(configuration.isEnabled == false)
        #expect(configuration.isArchived == false)
        #expect(await outbox.persistedSamples.isEmpty)
        let checkIn = try #require(try await store.recordingDeviceCheckIns().first)
        #expect(checkIn.lastAppliedPolicyChangeID == barrierID)
        #expect(checkIn.lastDiscardedPolicyChangeID == barrierID)
    }

    @Test func policyRevisionGapFailsClosedUntilTheMissingEventArrives() async throws {
        let pending = Self.pendingSample()
        let outbox = ScriptedLocationOutbox([pending])
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: false,
            outbox: outbox,
        )
        _ = try await Self.register(services)
        try await store.perform {
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: UUID(),
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [Self.initialPolicyID],
                revision: 2,
                issuedAt: Self.now,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: Self.now,
                state: .on,
                reason: .userCommand,
            ))
        }

        await #expect(throws: RecordingPersistenceError.self) {
            try await services.recording.reconcile(authorization: .always)
        }

        #expect(await services.ingestor.isActive == false)
        #expect(await outbox.persistedSamples == [pending])
    }

    @Test func oldInstallationDoesNotReplayInitialConsentInADestructiveEpoch() async throws {
        let (services, store) = try Self.makeServices(
            authorization: .always,
            initialEnabled: true,
        )
        _ = try await Self.register(services)
        let epoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: Self.remoteDeviceID,
                at: Self.now.addingTimeInterval(60),
            )
        }

        let configuration = try await Self.register(services)

        #expect(configuration.isArchived)
        #expect(configuration.latestPolicyChangeID == epoch.id.rawValue)
        #expect(configuration.device.status == .off)
        #expect(await services.ingestor.isActive == false)
        #expect(try await store.recordingPolicyChanges().isEmpty)
    }

    @Test func profileArrivingAfterDestructiveEpochStartsArchivedUntilExplicitlyReenabled(
    ) async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)
        let epoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: CurrentRecordingDevice.preview.id,
                at: Self.now.addingTimeInterval(60),
            )
        }
        try await store.perform {
            try await store.addRecordingDeviceProfile(RecordingDeviceProfile(
                id: Self.remoteDeviceID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: Self.now.addingTimeInterval(-3600),
                registrationEpochID: .initial,
            ))
        }

        let before = try await services.recording.devices()
        #expect(before.map(\.id) == [CurrentRecordingDevice.preview.id])
        #expect(before.first?.latestPolicyChangeID == epoch.id.rawValue)

        let after = try await services.recording.setEnabled(true, for: Self.remoteDeviceID)
        let remote = try #require(after.first(where: { $0.id == Self.remoteDeviceID }))
        #expect(remote.isEnabled == true)
        #expect(remote.isArchived == false)
        #expect(remote.isPending)
        let policy = try #require(
            try await store.recordingPolicyChanges().first(where: {
                $0.deviceID == Self.remoteDeviceID
            }),
        )
        #expect(policy.revision == 0)
        #expect(policy.reason == .userCommand)
    }

    @Test func storeChangeRefreshesARecordingHeartbeatAfterTheInterval() async throws {
        let clock = MutableRecordingTestClock(Self.now)
        let (services, store) = try Self.makeServices(
            authorization: .always,
            now: { clock.value },
        )
        _ = try await Self.register(services)
        await services.recording.startMonitoringPolicyChanges()
        clock.value = Self.now.addingTimeInterval(60 * 60)

        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: Self.now,
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }
        try await waitUntil {
            let checkIn = try? await store.recordingDeviceCheckIns().first
            return checkIn?.lastSeenAt == clock.value
        }

        let checkIn = try #require(try await store.recordingDeviceCheckIns().first)
        #expect(checkIn.lastSeenAt == clock.value)
    }

    @Test func storeChangeAppliesDestructiveEpochWithoutReplayingInitialConsent() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)
        await services.recording.startMonitoringPolicyChanges()
        let epoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: Self.remoteDeviceID,
                at: Self.now.addingTimeInterval(60),
            )
        }

        try await waitUntil {
            let checkIn = try? await store.recordingDeviceCheckIns().first
            return checkIn?.lastAppliedPolicyChangeID == epoch.id.rawValue
        }
        #expect(try await store.recordingPolicyChanges().isEmpty)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func reconcileWithoutRegistrationFailsClosed() async throws {
        let (services, _) = try Self.makeServices(authorization: .always)

        await #expect(throws: RecordingPersistenceError.self) {
            try await services.recording.reconcile(authorization: .always)
        }

        #expect(await services.ingestor.isActive == false)
    }

    @Test func replaceRecoveryPreservesImportedPolicyWithoutReplayingLocalConsent() async throws {
        let clock = MutableRecordingTestClock(Self.now)
        let (services, store) = try Self.makeServices(
            authorization: .always,
            now: { clock.value },
        )
        _ = try await Self.register(services)

        try await services.recording.pause()
        let importedPolicyID = try #require(
            UUID(uuidString: "99999999-9999-9999-9999-999999999999"),
        )
        let importedAt = Self.now.addingTimeInterval(60)
        try await store.perform {
            _ = try await store.rotateDataEpoch(
                reason: .backupReplace,
                changedBy: Self.remoteDeviceID,
                at: importedAt,
            )
            try await store.addRecordingPolicyChange(RecordingPolicyChange(
                id: importedPolicyID,
                deviceID: CurrentRecordingDevice.preview.id,
                parentIDs: [],
                revision: 0,
                issuedAt: importedAt,
                issuedByDeviceID: Self.remoteDeviceID,
                effectiveAt: importedAt,
                state: .off,
                reason: .initialRegistration,
            ))
        }
        clock.value = Self.now.addingTimeInterval(3600)

        try await services.recording.resumeAfterImport(discardPendingSamples: true)

        let profile = try #require(try await store.recordingDeviceProfiles().first)
        #expect(profile.registeredAt == Self.now)
        let policies = try await store.recordingPolicyChanges()
        #expect(policies.map(\.id) == [importedPolicyID])
        let checkIn = try #require(try await store.recordingDeviceCheckIns().first)
        #expect(checkIn.lastAppliedPolicyChangeID == importedPolicyID)
        #expect(checkIn.status == .off)
        #expect(await services.ingestor.isActive == false)
    }

    @Test func pausedControllerCannotMutateTheNewEpochAfterReset() async throws {
        let (services, store) = try Self.makeServices(authorization: .always)
        _ = try await Self.register(services)

        try await services.recording.pause()
        try await store.perform {
            _ = try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: CurrentRecordingDevice.preview.id,
                at: Self.now.addingTimeInterval(60),
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await services.recording.devices()
        }
        #expect(try await store.recordingDevices().count == 1)
        #expect(try await store.recordingPolicyChanges().isEmpty)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("waitUntil timed out")
    }
}

private final class MutableRecordingTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
