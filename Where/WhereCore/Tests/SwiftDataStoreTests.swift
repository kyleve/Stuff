import Foundation
import RegionKit
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

/// `SwiftDataStore` behavior as a `WhereStore` — specifically the `changes()`
/// signal that backs the app's single read-refresh path. The fan-out itself is
/// covered by `StoreChangeBroadcasterTests`; here we assert the *store* fires it
/// on a committed `perform` and stays silent on a rolled-back one.
struct SwiftDataStoreTests {
    @Test func inspectorStoreURLUsesTheResolvedAppGroupRoot() {
        let groupURL = FileManager.default.temporaryDirectory.appending(
            path: "where-group-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )

        #expect(
            SwiftDataStore.inspectorStoreURL(groupContainerURL: groupURL)
                == groupURL.appending(
                    path: "Library/Application Support/default.store",
                    directoryHint: .notDirectory,
                ),
        )
    }

    private static let calendar = WhereCoreTestSupport.calendar()
    private static let epochWriterID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )

    private let day = DayPresence(
        date: Date(timeIntervalSince1970: 0),
        in: SwiftDataStoreTests.calendar,
        regions: [.california],
    )

    @Test func committedWritePingsChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        // Subscribe before writing so the continuation exists when the commit
        // fires; the stream buffers the newest ping, so iterating after still
        // sees it.
        let stream = store.changes()

        try await store.perform { try await store.setManualDay(day) }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    @Test func nestedPerformStillPingsOnCommit() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A nested `perform` reuses the in-flight transaction; only the
        // outermost commit pings, so the consumer still gets its signal.
        try await store.perform {
            try await store.perform { try await store.setManualDay(day) }
        }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// Two (or more) *outermost* `perform` calls issued from independent tasks
    /// must be serialized. Because `perform`'s block is `async` and the store is
    /// an `actor`, naive reentrancy once let a concurrent top-level `perform`
    /// observe the in-flight peer, take the nested-reuse branch, and then trap in
    /// `mutationContext()` when the real owner cleared the peer out from under it
    /// (the shipped crash). Every transaction must now run to completion one at a
    /// time, and every write must commit.
    @Test func concurrentOutermostPerformsSerializeAndAllCommit() async throws {
        let store = try SwiftDataStore.inMemory()
        let observer = ConcurrencyObserver()
        let count = 30

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< count {
                group.addTask {
                    try await store.perform {
                        await observer.enter()
                        // Yield inside the transaction to widen the reentrancy
                        // window the serialization gate must hold shut.
                        await Task.yield()
                        try await store.setManualDay(DayPresence(
                            date: Date(timeIntervalSince1970: TimeInterval(index) * 86400),
                            in: Self.calendar,
                            regions: [.california],
                        ))
                        await observer.exit()
                    }
                }
            }
            try await group.waitForAll()
        }

        // No two transactions were ever in flight simultaneously...
        #expect(await observer.maxConcurrent == 1)
        // ...and every write committed (the old bug lost or crashed on writes).
        let stored = try await store.allManualDays()
        #expect(stored.count == count)
    }

    @Test func unrelatedReadCannotSeeAnotherTasksPendingTransaction() async throws {
        let store = try SwiftDataStore.inMemory()
        let pending = LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let writer = Task {
            try await store.perform {
                try await store.add(sample: pending)
                // Suspend while `writerContext` exists, widening the exact actor-reentrancy
                // window where an unrelated read once selected that uncommitted peer.
                startedContinuation.yield()
                startedContinuation.finish()
                for await _ in release {
                    break
                }
            }
        }
        for await _ in started {
            break
        }

        #expect(try await store.allSamples().isEmpty)

        releaseContinuation.yield()
        releaseContinuation.finish()
        try await writer.value
        #expect(try await store.allSamples() == [pending])
    }

    @Test func rolledBackWriteDoesNotPingChanges() async throws {
        let store = try SwiftDataStore.inMemory()
        let stream = store.changes()

        // A throwing transaction discards the peer context without saving, so
        // nothing reaches the persistent store and no ping should fire.
        await #expect(throws: CancellationError.self) {
            try await store.perform {
                try await store.setManualDay(self.day)
                throw CancellationError()
            }
        }

        #expect(await !firstPing(stream, within: .milliseconds(200)))
    }

    @Test func recordingDeviceAndAssignmentRowsRoundTripWithoutDuplicateLogicalRows() async throws {
        let store = try SwiftDataStore.inMemory()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let assignmentID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let profile = RecordingDeviceProfile(
            id: deviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: date,
            registrationEpochID: .initial,
        )
        let nicknameMetadata = try RecordingDeviceMetadataChange(
            id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
            deviceID: deviceID,
            revision: 0,
            changedAt: date,
            changedByDeviceID: deviceID,
            nickname: "Home iPad",
        )
        let checkIn = RecordingDeviceCheckIn(
            deviceID: deviceID,
            revision: 0,
            lastSeenAt: date,
            appliedAt: date,
            lastAppliedAssignmentChangeID: assignmentID,
            status: .off,
        )
        let assignment = RecordingAssignmentChange(
            id: assignmentID,
            parentIDs: [],
            revision: 0,
            issuedAt: date,
            issuedByDeviceID: deviceID,
            effectiveAt: date,
            assignedDeviceID: nil,
            reason: .onboarding,
        )

        try await store.perform {
            try await store.addRecordingDeviceProfile(profile)
            try await store.addRecordingDeviceProfile(profile)
            try await store.addRecordingDeviceMetadataChange(nicknameMetadata)
            try await store.addRecordingDeviceMetadataChange(nicknameMetadata)
            try await store.setRecordingDeviceCheckIn(checkIn)
            try await store.setRecordingDeviceCheckIn(checkIn)
            try await store.addRecordingAssignmentChange(assignment)
            try await store.addRecordingAssignmentChange(assignment)
        }

        #expect(try await store.recordingDeviceProfiles() == [profile])
        #expect(try await store.recordingDeviceMetadataChanges() == [nicknameMetadata])
        #expect(try await store.recordingDeviceCheckIns() == [checkIn])
        #expect(try await store.recordingDevices() == [RecordingDevice(
            id: deviceID,
            systemName: "iPad",
            nickname: "Home iPad",
            kind: .tablet,
            registeredAt: date,
            lastSeenAt: date,
            archivedAt: nil,
            lastAppliedAssignmentChangeID: assignmentID,
            status: .off,
        )])
        #expect(try await store.recordingAssignmentChanges() == [assignment])
    }

    /// A remote import (simulated via a scripted source) re-pings the same
    /// `changes()` fan-out a local commit does, so observers can't tell a sync
    /// from another device apart from a local write — one read path.
    @Test func remoteChangeForwardsToChanges() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        // The remote-change wiring is folded into the factory (there's no
        // public `startObservingRemoteChanges` to call), so the store observes
        // `source` from construction.
        let store = try SwiftDataStore.inMemory(remoteChangeSource: source)
        // Subscribe before emitting so the forwarded ping isn't missed.
        let stream = store.changes()

        source.yield()

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    @Test func simulatedRemoteRecordingImportIsReadableAfterRemoteChange() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        let store = try SwiftDataStore.inMemory(remoteChangeSource: source)
        let localWriteStream = store.changes()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let assignmentID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let profile = RecordingDeviceProfile(
            id: deviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: date,
            registrationEpochID: .initial,
        )
        let metadata = try RecordingDeviceMetadataChange(
            id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
            deviceID: deviceID,
            revision: 0,
            changedAt: date,
            changedByDeviceID: deviceID,
            nickname: "Travel iPad",
        )
        let checkIn = RecordingDeviceCheckIn(
            deviceID: deviceID,
            revision: 0,
            lastSeenAt: date,
            appliedAt: date,
            lastAppliedAssignmentChangeID: assignmentID,
            status: .recording,
        )
        let assignment = RecordingAssignmentChange(
            id: assignmentID,
            parentIDs: [],
            revision: 0,
            issuedAt: date,
            issuedByDeviceID: deviceID,
            effectiveAt: date,
            assignedDeviceID: deviceID,
            reason: .onboarding,
        )

        try await store.simulateRemoteRecordingImport(
            profiles: [profile],
            metadataChanges: [metadata],
            checkIns: [checkIn],
            assignmentChanges: [assignment],
            archives: [],
        )

        // The seam suppresses the ordinary local-commit ping: observers must
        // refresh through the same remote-change signal production CloudKit uses.
        #expect(await !firstPing(localWriteStream, within: .milliseconds(200)))
        let remoteChangeStream = store.changes()
        source.yield()
        #expect(await firstPing(remoteChangeStream, within: .seconds(2)))

        #expect(try await store.recordingDeviceProfiles() == [profile])
        #expect(try await store.recordingDeviceMetadataChanges() == [metadata])
        #expect(try await store.recordingDeviceCheckIns() == [checkIn])
        #expect(try await store.recordingAssignmentChanges() == [assignment])
        let device = try #require(try await store.recordingDevices().first)
        #expect(device.nickname == "Travel iPad")
        #expect(device.status == .recording)
        #expect(device.lastAppliedAssignmentChangeID == assignmentID)
    }

    @Test func newerCheckInRevisionWinsEvenWhenItsWallClockMovedBackward() async throws {
        let store = try SwiftDataStore.inMemory()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let firstPolicyID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let secondPolicyID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let first = RecordingDeviceCheckIn(
            deviceID: deviceID,
            revision: 0,
            lastSeenAt: Date(timeIntervalSinceReferenceDate: 200),
            appliedAt: Date(timeIntervalSinceReferenceDate: 200),
            lastAppliedAssignmentChangeID: firstPolicyID,
            status: .recording,
        )
        let causallyLater = RecordingDeviceCheckIn(
            deviceID: deviceID,
            revision: 1,
            lastSeenAt: Date(timeIntervalSinceReferenceDate: 100),
            appliedAt: Date(timeIntervalSinceReferenceDate: 100),
            lastAppliedAssignmentChangeID: secondPolicyID,
            status: .off,
        )

        try await store.perform { try await store.setRecordingDeviceCheckIn(first) }
        try await store.perform { try await store.setRecordingDeviceCheckIn(causallyLater) }

        #expect(try await store.recordingDeviceCheckIns() == [causallyLater])
    }

    @Test func malformedSyncedAuthorityFailsClosedWhileOtherRowsAreDropped() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        let deviceID = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let eventID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let date = Date(timeIntervalSinceReferenceDate: 100)

        let negativeMetadata = SDRecordingDeviceMetadataChange()
        negativeMetadata.id = eventID
        negativeMetadata.deviceID = deviceID
        negativeMetadata.fieldRaw = RecordingDeviceMetadataField.nickname.rawValue
        negativeMetadata.revision = -1
        negativeMetadata.changedAt = date
        negativeMetadata.changedByDeviceID = deviceID

        let combinedMetadata = SDRecordingDeviceMetadataChange()
        combinedMetadata.id = UUID()
        combinedMetadata.deviceID = deviceID
        combinedMetadata.fieldRaw = "removed-archive-field"
        combinedMetadata.revision = 0
        combinedMetadata.changedAt = date
        combinedMetadata.changedByDeviceID = deviceID
        combinedMetadata.nickname = "iPad"

        let checkIn = SDRecordingDeviceCheckIn()
        checkIn.deviceID = deviceID
        checkIn.revision = -1
        checkIn.lastSeenAt = date
        checkIn.appliedAt = date
        checkIn.lastAppliedAssignmentChangeID = eventID
        checkIn.statusRaw = RecordingDeviceStatus.off.rawValue

        context.insert(negativeMetadata)
        context.insert(combinedMetadata)
        context.insert(checkIn)
        try context.save()
        let store = SwiftDataStore(modelContainer: container)

        #expect(try await store.recordingDeviceMetadataChanges().isEmpty)
        #expect(try await store.recordingDeviceCheckIns().isEmpty)
    }

    @Test func newMultiParentRowsFailClosedWhileTheirParentArrayIsUnavailable() {
        let firstEpochParent = Self.epochID("10000000-0000-0000-0000-000000000000")
        let secondEpochParent = Self.epochID("20000000-0000-0000-0000-000000000000")
        let epoch = Self.epoch(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [firstEpochParent, secondEpochParent],
            revision: 2,
            changedAt: Date(timeIntervalSinceReferenceDate: 300),
            reason: .backupReplace,
        )
        let epochRow = SDWhereDataEpoch(value: epoch)
        #expect(epochRow.parentID == nil)
        #expect(epochRow.parentIDs == [
            firstEpochParent.rawValue,
            secondEpochParent.rawValue,
        ])
        epochRow.parentIDs = nil

        #expect(epochRow.toValue() == nil)
    }

    @Test func legacyScalarParentsStillDecodeAsSingleParentArrays() throws {
        let epochID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))
        let epochRow = SDWhereDataEpoch()
        epochRow.id = epochID
        epochRow.parentID = WhereDataEpochID.initial.rawValue
        epochRow.parentIDs = nil
        epochRow.revision = 1
        epochRow.changedAt = Date(timeIntervalSinceReferenceDate: 100)
        epochRow.changedByDeviceID = Self.epochWriterID.rawValue
        epochRow.reasonRaw = WhereDataEpochReason.accountReset.rawValue

        #expect(try #require(epochRow.toValue()).parentIDs == [.initial])
    }

    @Test func lateRowsFromASupersededEpochCannotRepopulateAnySyncedUserData() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let policyID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let date = Date(timeIntervalSinceReferenceDate: 100)
        let sample = LocationSample(
            timestamp: date,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
        )
        let evidence = try Evidence(
            id: #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")),
            kind: .boardingPass,
            capturedAt: date,
            region: .california,
            note: nil,
            contentType: .pdf,
        )
        let manualDay = DayPresence(
            date: date,
            in: Self.calendar,
            regions: [.california],
        )
        let dismissal = DismissedIssue(
            id: .borderDrift(day: manualDay.day),
            dismissedAt: date,
        )
        let profile = RecordingDeviceProfile(
            id: deviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: date,
            registrationEpochID: .initial,
        )
        let metadata = try RecordingDeviceMetadataChange(
            id: #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")),
            deviceID: deviceID,
            revision: 0,
            changedAt: date,
            changedByDeviceID: deviceID,
            nickname: "Home iPad",
        )
        let checkIn = RecordingDeviceCheckIn(
            deviceID: deviceID,
            revision: 0,
            lastSeenAt: date,
            appliedAt: date,
            lastAppliedAssignmentChangeID: policyID,
            status: .recording,
        )
        let assignment = RecordingAssignmentChange(
            id: policyID,
            parentIDs: [],
            revision: 0,
            issuedAt: date,
            issuedByDeviceID: deviceID,
            effectiveAt: date,
            assignedDeviceID: deviceID,
            reason: .onboarding,
        )

        let epoch = try await store.perform {
            try await store.addRecordingDeviceProfile(profile)
            return try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: deviceID,
                at: date.addingTimeInterval(1),
            )
        }

        // Model a device that was offline during reset and uploads its complete old snapshot
        // afterward. Remote CloudKit writes do not pass through WhereStore's mutation methods,
        // so insert the old-generation records at the SwiftData boundary just as an import does.
        let remoteContext = ModelContext(container)
        remoteContext.insert(SDLocationSample(value: sample, epochID: .initial))
        remoteContext.insert(SDEvidence(value: evidence, blob: Data("old".utf8), epochID: .initial))
        remoteContext.insert(SDManualDay(value: manualDay, epochID: .initial))
        remoteContext.insert(SDDismissedIssue(
            key: dismissal.id.storeURL.absoluteString,
            dismissedAt: dismissal.dismissedAt,
            epochID: .initial,
        ))
        remoteContext.insert(SDTrackedRegion(regionID: "us-TX", epochID: .initial))
        remoteContext.insert(SDRecordingDeviceMetadataChange(value: metadata, epochID: .initial))
        remoteContext.insert(SDRecordingDeviceCheckIn(value: checkIn, epochID: .initial))
        remoteContext.insert(SDRecordingAssignmentChange(value: assignment, epochID: .initial))
        try remoteContext.save()

        let reader = SwiftDataStore(modelContainer: container)
        #expect(try await reader.dataEpoch() == epoch)
        #expect(try await reader.allSamples().isEmpty)
        #expect(try await reader.allEvidence().isEmpty)
        #expect(try await reader.evidenceBlob(for: evidence.id) == nil)
        #expect(try await reader.allManualDays().isEmpty)
        #expect(try await reader.allDismissedIssues().isEmpty)
        #expect(try await reader.trackedRegions() == SwiftDataStore.defaultTrackedRegions)
        #expect(try await reader.recordingDeviceProfiles() == [profile])
        #expect(try await reader.recordingDeviceMetadataChanges().isEmpty)
        #expect(try await reader.recordingDeviceCheckIns().isEmpty)
        #expect(try await reader.recordingAssignmentChanges().isEmpty)
    }

    @Test func expectedEpochTransactionRejectsStaleAuthorityWithoutWriting() async throws {
        let store = try SwiftDataStore.inMemory()
        let staleEpochID = try await (store.dataEpoch()).id
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let currentEpoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: deviceID,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }
        let sample = LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 200),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )

        #expect(currentEpoch.id != staleEpochID)
        await #expect(throws: RecordingPersistenceError.dataEpochChanged) {
            try await store.perform(expectedDataEpochID: staleEpochID) {
                try await store.add(sample: sample)
            }
        }
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func epochRotationClampsABackwardClockToItsParentBoundary() async throws {
        let store = try SwiftDataStore.inMemory()
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let parentDate = Date(timeIntervalSinceReferenceDate: 200)
        let parent = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: deviceID,
                at: parentDate,
            )
        }

        let child = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .backupReplace,
                changedBy: deviceID,
                at: parentDate.addingTimeInterval(-100),
            )
        }

        #expect(child.parentIDs == [parent.id])
        #expect(child.changedAt == parentDate)
    }

    @Test func syntheticEpochRowsRequireTheExactResetFrontierAndAJoinRetiresThem() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let first = Self.epoch(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            reason: .accountReset,
        )
        let second = Self.epoch(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 200),
            reason: .accountReset,
        )
        let firstResolution = try WhereDataEpoch.resolve(in: [first, second])
        let syntheticDay = DayPresence(
            date: Date(timeIntervalSinceReferenceDate: 10000),
            in: Self.calendar,
            regions: [.california],
        )
        let initialContext = ModelContext(container)
        initialContext.insert(SDWhereDataEpoch(value: first))
        initialContext.insert(SDWhereDataEpoch(value: second))
        initialContext.insert(SDManualDay(
            value: syntheticDay,
            epochID: firstResolution.current.id,
        ))
        try initialContext.save()

        let firstReader = SwiftDataStore(modelContainer: container)
        #expect(try await firstReader.dataEpoch() == firstResolution.current)
        #expect(try await firstReader.allManualDays() == [syntheticDay])

        let third = Self.epoch(
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 300),
            reason: .accountReset,
        )
        let secondResolution = try WhereDataEpoch.resolve(in: [first, second, third])
        let thirdResetContext = ModelContext(container)
        thirdResetContext.insert(SDWhereDataEpoch(value: third))
        try thirdResetContext.save()

        let secondReader = SwiftDataStore(modelContainer: container)
        #expect(secondResolution.current.id != firstResolution.current.id)
        #expect(try await secondReader.dataEpoch() == secondResolution.current)
        #expect(try await secondReader.allManualDays().isEmpty)

        let replacement = Self.epoch(
            id: "40000000-0000-0000-0000-000000000000",
            parentIDs: [first.id, second.id, third.id],
            revision: 2,
            changedAt: Date(timeIntervalSinceReferenceDate: 400),
            reason: .backupReplace,
        )
        let replacementDay = DayPresence(
            date: Date(timeIntervalSinceReferenceDate: 20000),
            in: Self.calendar,
            regions: [.newYork],
        )
        let replacementContext = ModelContext(container)
        replacementContext.insert(SDWhereDataEpoch(value: replacement))
        replacementContext.insert(SDManualDay(value: replacementDay, epochID: replacement.id))
        try replacementContext.save()

        let replacementReader = SwiftDataStore(modelContainer: container)
        #expect(try await replacementReader.dataEpoch() == replacement)
        #expect(try await replacementReader.allManualDays() == [replacementDay])
    }

    @Test func rotationWritesOneCanonicalMultiParentNodeAndScopesFollowingRowsToIt() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let first = Self.epoch(
            id: "10000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            reason: .accountReset,
        )
        let second = Self.epoch(
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 200),
            reason: .accountReset,
        )
        let seedContext = ModelContext(container)
        seedContext.insert(SDWhereDataEpoch(value: first))
        seedContext.insert(SDWhereDataEpoch(value: second))
        try seedContext.save()

        let replacementDay = DayPresence(
            date: Date(timeIntervalSinceReferenceDate: 20000),
            in: Self.calendar,
            regions: [.newYork],
        )
        let store = SwiftDataStore(modelContainer: container)
        let replacement = try await store.perform {
            let epoch = try await store.rotateDataEpoch(
                reason: .backupReplace,
                changedBy: Self.epochWriterID,
                at: Date(timeIntervalSinceReferenceDate: 300),
            )
            try await store.setManualDay(replacementDay)
            return epoch
        }

        let inspectionContext = ModelContext(container)
        let epochRows = try inspectionContext.fetch(FetchDescriptor<SDWhereDataEpoch>())
        let replacementRows = epochRows.filter { $0.id == replacement.id.rawValue }
        let replacementRow = try #require(replacementRows.first)
        let manualRows = try inspectionContext.fetch(FetchDescriptor<SDManualDay>())

        #expect(replacement.parentIDs == [first.id, second.id])
        #expect(replacementRows.count == 1)
        #expect(replacementRow.parentID == nil)
        #expect(replacementRow.parentIDs == [first.id.rawValue, second.id.rawValue])
        #expect(manualRows.count == 1)
        #expect(manualRows.first?.epochID == replacement.id.rawValue)
        #expect(try await store.dataEpoch() == replacement)
        #expect(try await store.allManualDays() == [replacementDay])
    }

    @Test func importReceiptRemainsDiscoverableAfterItsEpochIsSuperseded() async throws {
        let store = try SwiftDataStore.inMemory()
        let transactionID = UUID()
        let installationID = RecordingDeviceID(rawValue: UUID())
        let originalEpochID = try await (store.dataEpoch()).id
        try await store.perform {
            try await store.addBackupImportReceipt(
                id: transactionID,
                installationID: installationID,
            )
        }

        _ = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: installationID,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }

        let receipt = try #require(try await store.backupImportReceipt(
            id: transactionID,
            installationID: installationID,
        ))
        #expect(receipt.dataEpochID == originalEpochID)
        #expect(try await store.backupImportReceipt(
            id: transactionID,
            installationID: RecordingDeviceID(rawValue: UUID()),
        ) == nil)
    }

    @Test func expectedEpochTransactionRejectsEpochImportedWhileBodyIsSuspended() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let sample = LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 200),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .manual,
        )
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let writer = Task {
            try await store.perform(expectedDataEpochID: .initial) {
                startedContinuation.yield()
                startedContinuation.finish()
                for await _ in release {
                    break
                }
                try await store.add(sample: sample)
            }
        }
        for await _ in started {
            break
        }

        let remoteContext = ModelContext(container)
        remoteContext.insert(SDWhereDataEpoch(value: WhereDataEpoch(
            id: WhereDataEpochID(rawValue: UUID()),
            parentIDs: [.initial],
            revision: 1,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            changedByDeviceID: deviceID,
            reason: .accountReset,
        )))
        try remoteContext.save()
        releaseContinuation.yield()
        releaseContinuation.finish()

        await #expect(throws: RecordingPersistenceError.dataEpochChanged) {
            try await writer.value
        }
        // The stale row may have committed before the post-save guard, but it
        // belongs to the losing epoch and is never visible as active data.
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func readSnapshotRejectsCommitBeforeNotification() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore.inMemory(
            modelContainer: container,
            remoteChangeSource: source,
        )
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let readObserver = SnapshotReadObserver()
        let snapshot = Task {
            try await store.readSnapshot {
                let first = try await store.allSamples()
                await readObserver.recordFirst(first.count)
                startedContinuation.yield()
                startedContinuation.finish()
                for await _ in release {
                    break
                }
                let second = try await store.allManualDays()
                await readObserver.recordSecond(second.count)
                return second
            }
        }
        for await _ in started {
            break
        }

        let remoteContext = ModelContext(container)
        remoteContext.insert(SDLocationSample(
            value: LocationSample(
                timestamp: Date(timeIntervalSince1970: 0),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .manual,
            ),
            epochID: .initial,
        ))
        remoteContext.insert(SDManualDay(value: day, epochID: .initial))
        try remoteContext.save()
        // Deliberately do not deliver the corresponding remote-change signal:
        // a store commit can be visible before Core Data posts its notification.
        // Persistent history is committed alongside the row, so the snapshot
        // must still reject the mixed pre/post-commit read.
        releaseContinuation.yield()
        releaseContinuation.finish()

        await #expect(throws: RecordingPersistenceError.dataEpochChanged) {
            try await snapshot.value
        }
        #expect(await readObserver.counts == [0, 1])
    }

    @Test func readSnapshotAllowsDelayedNotificationForIncludedCommit() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let remoteContext = ModelContext(container)
        remoteContext.insert(SDManualDay(value: day, epochID: .initial))
        try remoteContext.save()
        let store = SwiftDataStore.inMemory(
            modelContainer: container,
            remoteChangeSource: source,
        )
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let snapshot = Task {
            try await store.readSnapshot {
                _ = try await store.allManualDays()
                startedContinuation.yield()
                startedContinuation.finish()
                for await _ in release {
                    break
                }
                return try await store.allManualDays()
            }
        }
        for await _ in started {
            break
        }

        // The commit is already part of the snapshot's starting history head.
        // Its delayed notification is refresh-only and must not invalidate a
        // consistent read whose durable store generation has not changed.
        source.yield()
        releaseContinuation.yield()
        releaseContinuation.finish()

        #expect(try await snapshot.value == [day])
    }

    @Test func inactiveEvidenceBlobIsNotResurrectedByMetadataOnlyActiveWrite() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let currentEpoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: deviceID,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }
        let evidence = try Evidence(
            id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            kind: .boardingPass,
            capturedAt: Date(timeIntervalSinceReferenceDate: 200),
            region: .california,
            note: "Restored metadata",
            contentType: .pdf,
        )
        let inactiveBlob = Data("inactive attachment".utf8)
        let remoteContext = ModelContext(container)
        remoteContext.insert(SDEvidence(
            value: evidence,
            blob: inactiveBlob,
            epochID: .initial,
        ))
        try remoteContext.save()

        try await store.perform(expectedDataEpochID: currentEpoch.id) {
            try await store.write(evidence: evidence, blob: nil)
        }

        #expect(try await store.allEvidence() == [evidence])
        #expect(try await store.evidenceBlob(for: evidence.id) == nil)
    }

    /// Reusing an inactive row would also reuse its CloudKit record identity. A delayed
    /// tombstone from the old generation could then delete current restored data, so every
    /// same-id write must preserve the inactive row and create a current-epoch record.
    @Test func inactiveSameIDRowsRemainSeparateFromCurrentEpochUpserts() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let policyID = try #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let metadataID = try #require(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let sampleID = try #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
        let date = Date(timeIntervalSinceReferenceDate: 200)
        let sample = LocationSample(
            id: sampleID,
            timestamp: date,
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsVisit,
            recordingDeviceID: deviceID,
        )
        let metadata = try RecordingDeviceMetadataChange(
            id: metadataID,
            deviceID: deviceID,
            revision: 0,
            changedAt: date,
            changedByDeviceID: deviceID,
            nickname: "Home iPad",
        )
        let assignment = RecordingAssignmentChange(
            id: policyID,
            parentIDs: [],
            revision: 0,
            issuedAt: date,
            issuedByDeviceID: deviceID,
            effectiveAt: date,
            assignedDeviceID: nil,
            reason: .onboarding,
        )
        let currentEpoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: deviceID,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }

        let remoteContext = ModelContext(container)
        remoteContext.insert(SDLocationSample(value: sample, epochID: .initial))
        remoteContext.insert(SDRecordingDeviceMetadataChange(value: metadata, epochID: .initial))
        remoteContext.insert(SDRecordingAssignmentChange(value: assignment, epochID: .initial))
        try remoteContext.save()

        try await store.perform(expectedDataEpochID: currentEpoch.id) {
            try await store.add(sample: sample)
            try await store.addRecordingDeviceMetadataChange(metadata)
            try await store.addRecordingAssignmentChange(assignment)
        }

        let inspectionContext = ModelContext(container)
        let sampleRows = try inspectionContext.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate { $0.id == sampleID }),
        )
        let metadataRows = try inspectionContext.fetch(
            FetchDescriptor<SDRecordingDeviceMetadataChange>(predicate: #Predicate {
                $0.id == metadataID
            }),
        )
        let assignmentRows = try inspectionContext.fetch(
            FetchDescriptor<SDRecordingAssignmentChange>(predicate: #Predicate {
                $0.id == policyID
            }),
        )
        let expectedEpochIDs = Set([
            WhereDataEpochID.initial.rawValue,
            currentEpoch.id.rawValue,
        ])

        #expect(sampleRows.count == 2)
        #expect(Set(sampleRows.compactMap(\.epochID)) == expectedEpochIDs)
        #expect(metadataRows.count == 2)
        #expect(Set(metadataRows.compactMap(\.epochID)) == expectedEpochIDs)
        #expect(assignmentRows.count == 2)
        #expect(Set(assignmentRows.compactMap(\.epochID)) == expectedEpochIDs)
        #expect(try await store.allSamples() == [sample])
        #expect(try await store.recordingDeviceMetadataChanges() == [metadata])
        #expect(try await store.recordingAssignmentChanges() == [assignment])
    }

    @Test func duplicateProfilesResolveDeterministicallyByRegistrationEpoch() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        let deviceID = RecordingDeviceID(rawValue: UUID())
        let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
        let earlierCanonicalEpoch = try WhereDataEpochID(rawValue: #require(UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        )))
        let laterCanonicalEpoch = try WhereDataEpochID(rawValue: #require(UUID(
            uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
        )))
        let winner = RecordingDeviceProfile(
            id: deviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: registeredAt,
            registrationEpochID: earlierCanonicalEpoch,
        )
        let duplicate = RecordingDeviceProfile(
            id: deviceID,
            systemName: "iPad",
            kind: .tablet,
            registeredAt: registeredAt,
            registrationEpochID: laterCanonicalEpoch,
        )
        context.insert(SDRecordingDeviceProfile(value: duplicate))
        context.insert(SDRecordingDeviceProfile(value: winner))
        try context.save()

        let store = SwiftDataStore(modelContainer: container)
        #expect(try await store.recordingDeviceProfiles() == [winner])
    }

    @Test func incompleteEpochHistoryFailsClosed() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        context.insert(SDWhereDataEpoch(value: WhereDataEpoch(
            id: WhereDataEpochID(rawValue: UUID()),
            parentIDs: [.initial],
            revision: 2,
            changedAt: Date(timeIntervalSinceReferenceDate: 100),
            changedByDeviceID: RecordingDeviceID(rawValue: UUID()),
            reason: .accountReset,
        )))
        try context.save()

        let store = SwiftDataStore(modelContainer: container)
        await #expect(throws: RecordingPersistenceError.incompleteDataEpochHistory) {
            try await store.dataEpoch()
        }
    }

    /// Once `perform`'s `peer.save()` returns, the committed write must be
    /// visible to a later read through the main (read) context — the question
    /// raised in review (`send()` after `save()` is only useful if readers then
    /// observe the data). The subtle case is an *update* to a row a prior read
    /// already registered in that long-lived read context, where a stale cached
    /// instance could shadow the new value: insert, read (registering the row),
    /// update the same day, then read again and require the *updated* regions —
    /// not the originally-read ones.
    @Test func committedWriteIsVisibleToALaterRead() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)

        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.california],
            ))
        }
        let afterInsert = try await store.allManualDays()
        #expect(afterInsert.count == 1)
        #expect(afterInsert.first?.regions == [.california])

        // Same `date` key, so this replaces the row the read above registered.
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.newYork],
            ))
        }
        let afterUpdate = try await store.allManualDays()
        #expect(afterUpdate.count == 1)
        #expect(afterUpdate.first?.regions == [.newYork])
    }

    @Test func localCommitCarriesTheHistoryAuthorUsedByRemoteFiltering() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)

        try await store.perform {
            try await store.setManualDay(day)
        }

        let historyContext = ModelContext(container)
        let transactions = try historyContext.fetchHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(),
        )
        let latest = try #require(transactions.max {
            $0.transactionIdentifier < $1.transactionIdentifier
        })
        #expect(latest.author?.hasPrefix("where-") == true)
    }

    @Test func auditRoundTripsThroughAManualDay() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let audit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 1000),
            note: "Filed after reviewing receipts.",
            location: CapturedLocation(
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 8,
                timestamp: Date(timeIntervalSince1970: 990),
            ),
        )

        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.newYork],
                    isAuthoritative: true,
                    audit: audit,
                ),
            )
        }

        let stored = try await store.allManualDays()
        #expect(stored.first?.audit == audit)
    }

    @Test func auditWithoutLocationRoundTripsAsNoteOnly() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let audit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 1000),
            note: "No GPS fix was available.",
            location: nil,
        )

        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: date,
                in: Self.calendar,
                regions: [.california],
                audit: audit,
            ))
        }

        let stored = try await store.allManualDays()
        #expect(stored.first?.audit == audit)
        #expect(stored.first?.audit?.location == nil)
    }

    /// An additive backfill can't downgrade an authoritative row's regions, but
    /// its (newer) audit must still win — the trail tracks the latest action.
    @Test func additiveBackfillOverAuthoritativeKeepsIncomingAudit() async throws {
        let store = try SwiftDataStore.inMemory()
        let date = Date(timeIntervalSince1970: 0)
        let firstAudit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 100),
            note: "Original override.",
            location: nil,
        )
        let laterAudit = ManualEntryAudit(
            recordedAt: Date(timeIntervalSince1970: 200),
            note: "Later backfill sweep.",
            location: nil,
        )

        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.california],
                    isAuthoritative: true,
                    audit: firstAudit,
                ),
            )
        }
        try await store.perform {
            try await store.setManualDay(
                DayPresence(
                    date: date,
                    in: Self.calendar,
                    regions: [.newYork],
                    isAuthoritative: false,
                    audit: laterAudit,
                ),
            )
        }

        let stored = try await store.allManualDays()
        #expect(stored.count == 1)
        // Regions can't be downgraded (stays authoritative, unions in the backfill)...
        #expect(stored.first?.isAuthoritative == true)
        #expect(stored.first?.regions == [.california, .newYork])
        // ...but the newer audit wins.
        #expect(stored.first?.audit == laterAudit)
    }

    private static func epoch(
        id: String,
        parentIDs: [WhereDataEpochID],
        revision: Int64,
        changedAt: Date,
        reason: WhereDataEpochReason,
    ) -> WhereDataEpoch {
        WhereDataEpoch(
            id: epochID(id),
            parentIDs: parentIDs,
            revision: revision,
            changedAt: changedAt,
            changedByDeviceID: epochWriterID,
            reason: reason,
        )
    }

    private static func epochID(_ value: String) -> WhereDataEpochID {
        WhereDataEpochID(rawValue: UUID(uuidString: value)!)
    }
}

/// Tracks the peak number of concurrently-executing transaction blocks so a
/// test can assert `perform` serialized them (peak of 1). `enter`/`exit`
/// bracket the block body.
private actor ConcurrencyObserver {
    private var current = 0
    private(set) var maxConcurrent = 0

    func enter() {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
    }

    func exit() {
        current -= 1
    }
}

/// Captures both table reads from a snapshot that is expected to throw during
/// its final generation validation, so the regression can prove the reads did
/// straddle one atomic external transaction.
private actor SnapshotReadObserver {
    private(set) var counts: [Int] = []

    func recordFirst(_ count: Int) {
        counts = [count]
    }

    func recordSecond(_ count: Int) {
        counts.append(count)
    }
}

/// Awaits the first `changes()` ping, returning `false` if none arrives within
/// `budget`. Races the stream against a timeout so a missing ping fails fast
/// instead of hanging the test.
private func firstPing(_ stream: AsyncStream<Void>, within budget: Duration) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: budget)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
