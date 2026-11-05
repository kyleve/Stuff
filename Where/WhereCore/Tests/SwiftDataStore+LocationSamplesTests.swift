import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct SwiftDataStoreLocationSamplesTests {
    @Test func lateObservationPreservesRawEvidenceWhenItRevealsAnInvalidControlDependency(
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let decision = try RecordingAssessmentTestSupport.decision(
            16,
            predecessors: [.init(rawValue: sample.id)],
        )
        let control = try RecordingControlCodec.encode(.source(decision), generationID: .initial)
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            try await store.addVersionedHistoryRecord(control)
        }
        let controls = RecordingControlStore(
            store: store,
            policy: RecordingBackupTestSupport.policy,
        )
        #expect(try await controls.snapshot().sourceChoices == [decision])
        // Sensor evidence must survive even when its arrival proves an existing control invalid.
        // Selection fails observably instead of deleting either observation or control.
        try await store.perform { try await store.add(sample: sample) }
        #expect(try await store.allSamples() == [sample])
        await #expect(throws: DataCompatibilityError.conflictingRecord) {
            try await controls.snapshot()
        }
        #expect(try await store.versionedHistoryRecords(policy: RecordingBackupTestSupport.policy)
            .contains(control))
    }

    @Test @MainActor func observationBeforeSharedFloorBlocksAFoundationReader() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 0,
            policy: .foundation,
            onFailure: { _, _ in },
        )
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let envelope = try VersionedLocationSample.encode(sample, generationID: .initial)
        let context = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(envelope)
        context.insert(row)
        try context.save() // The source's global requirement has not arrived.
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == nil)
        #expect(try await store.dataCompatibilityState().recordMajors == [1])
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 1)) {
            try await access.store.allSamples()
        }
        #expect(access.isRevoked)
        #expect(try await store.allSamples() == [sample])
        #expect(try await RecordingControlStore(
            store: store,
            policy: RecordingBackupTestSupport.policy,
        ).snapshot().records.isEmpty)
    }

    @Test @MainActor func majorOneWritesUseOnlyTheAtomicObservationEnvelope() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            try await store.add(sample: sample)
            try await store.add(sample: sample)
        }
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<SDLocationSample>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SDVersionedHistoryRecord>()) == 1)
        #expect(try await store
            .samples(in: DateInterval(start: sample.timestamp, duration: 1)) == [sample])
        #expect(try await store.samples(in: DateInterval(
            start: sample.timestamp.addingTimeInterval(-1),
            end: sample.timestamp,
        )).isEmpty)
    }

    @Test @MainActor func clearingVersionedGPSPreservesFloorAndResetsItsCorrectionForLateReplay(
    ) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let context = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(VersionedLocationSample.encode(
            sample,
            generationID: .initial,
        ))
        context.insert(row)
        try context.save()
        try await store.perform {
            try await store.addSampleAttributionRevision(.init(
                id: .init(rawValue: UUID()),
                sampleID: sample.id,
                updatedAt: sample.timestamp,
                replacementRegions: [],
            ))
        }
        let day = try #require(sample.recordingDay?.day)
        try await store.perform {
            try await store.clear(
                in: DateInterval(start: sample.timestamp, duration: 1),
                manualDays: day ... day,
            )
        }
        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == 1)
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<SDVersionedHistoryRecord>()) == 0)
        let revisions = try await store.allSampleAttributionRevisions()
        #expect(revisions.contains { $0.sampleID == sample.id && $0.replacementRegions == nil })
        try await store.perform { try await store.add(sample: sample) }
        #expect(try await store.allSamples() == [sample])
    }
}

extension SwiftDataStoreLocationSamplesTests {
    @Test func legacyIdentityIndexTracksUpdatesClearsAndGenerationRotation() async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let replacement = LocationSample(
            id: sample.id,
            timestamp: sample.timestamp,
            coordinate: .init(latitude: 50, longitude: 10),
            horizontalAccuracy: sample.horizontalAccuracy,
            source: sample.source,
            recordingDeviceID: sample.recordingDeviceID,
            motion: sample.motion,
            recordingDay: sample.recordingDay,
        )
        let day = try #require(sample.recordingDay?.day)
        try await store.perform {
            try await store.add(sample: sample)
            try await store.add(sample: replacement)
            #expect(try await store.allSamples() == [replacement])
            try await store.clear(
                in: DateInterval(start: sample.timestamp, duration: 1),
                manualDays: day ... day,
            )
            #expect(try await store.allSamples().isEmpty)
            try await store.add(sample: sample)
            #expect(try await store.allSamples() == [sample])
            _ = try await store.rotateDataGeneration(
                reason: .backupReplace,
                changedBy: RecordingControlsTestSupport.device,
                at: sample.timestamp,
            )
            #expect(try await store.allSamples().isEmpty)
            try await store.add(sample: replacement)
            #expect(try await store.allSamples() == [replacement])
        }
        #expect(try await store.allSamples() == [replacement])
    }

    @Test(arguments: [1000, 4000])
    func bulkObservationWritesAndRetriesShareOneTransactionIndex(count: Int) async throws {
        let fixture = try RecordingPersistenceTestSupport()
        defer { fixture.remove() }
        let store = SwiftDataStore(modelContainer: fixture.container)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 1,
            policy: RecordingBackupTestSupport.policy,
            onFailure: { _, _ in },
        )
        let samples = (0 ..< count).map { number in
            LocationSample(
                id: UUID(),
                timestamp: Date(timeIntervalSinceReferenceDate: Double(number)),
                coordinate: .init(latitude: 40, longitude: -74),
                horizontalAccuracy: 10,
                source: .gpsVisit,
                recordingDeviceID: RecordingControlsTestSupport.device,
                recordingDay: .unresolved,
            )
        }
        for _ in 0 ..< 2 {
            let builds = try await access.store.perform {
                let before = await store.versionedHistoryIndexBuildCount
                for sample in samples {
                    try await access.store.add(sample: sample)
                }
                try await access.store.readSnapshot {
                    let loaded = try await access.store.allSamples()
                    let records = try await access.store
                        .versionedHistoryRecords(policy: RecordingBackupTestSupport.policy)
                    #expect(Set(loaded) == Set(samples))
                    #expect(records.count == count)
                }
                return await store.versionedHistoryIndexBuildCount - before
            }
            #expect(builds == 1)
        }
    }

    @Test func delayedConflictingRetiredObservationsRemainInertAfterRotation() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let original = try VersionedLocationSample.encode(sample, generationID: .initial)
        let conflicting = VersionedHistoryRecord(
            id: original.id,
            dataGenerationID: .initial,
            semantics: original.semantics,
            scope: original.scope,
            kind: original.kind,
            payload: Data("different retired payload".utf8),
        )
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingControlsTestSupport.device,
                at: Date(),
            )
        }
        let remote = ModelContext(container)
        for record in [original, conflicting] {
            let row = SDVersionedHistoryRecord()
            row.envelope = try JSONEncoder().encode(record)
            remote.insert(row)
        }
        try remote.save()
        #expect(try await store.allSamples().isEmpty)
        let controls = RecordingControlStore(
            store: store,
            policy: RecordingBackupTestSupport.policy,
        )
        #expect(try await controls.snapshot().records.isEmpty)
        try await store.perform { try await store.add(sample: sample) }
        #expect(try await store.allSamples() == [sample])
        #expect(try await controls.snapshot().records.isEmpty)
    }

    @Test(arguments: [false, true])
    func aSuspendedIndexNeverLeaksToAnotherTaskOrSurvivesRollback(rollsBack: Bool) async throws {
        enum Rollback: Error { case requested }
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let gate = CompatibilityTestGate()
        let write = Task {
            try await store.perform {
                try await store.add(sample: sample)
                await gate.suspend()
                if rollsBack { throw Rollback.requested }
            }
        }
        await gate.waitUntilEntered()
        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.dataCompatibilityState().recordMajors.isEmpty)
        await gate.resume()
        if rollsBack {
            await #expect(throws: Rollback.requested) { try await write.value }
            #expect(try await store.allSamples().isEmpty)
            // The discarded identity must not collide with a later transaction's different data.
            let replacement = LocationSample(
                id: sample.id,
                timestamp: sample.timestamp,
                coordinate: .init(latitude: 50, longitude: 10),
                horizontalAccuracy: 20,
                source: sample.source,
                recordingDeviceID: sample.recordingDeviceID,
                motion: sample.motion,
                recordingDay: sample.recordingDay,
            )
            try await store.perform { try await store.add(sample: replacement) }
            #expect(try await store.allSamples() == [replacement])
        } else {
            try await write.value
            #expect(try await store.allSamples() == [sample])
        }
    }

    @Test(arguments: [false, true])
    func importedEnvelopeAfterIndexCreationCannotPassTheCommitGuard(newerMajor: Bool) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 1,
            policy: RecordingBackupTestSupport.policy,
            onFailure: { _, _ in },
        )
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let gate = CompatibilityTestGate()
        let operation = Task {
            try await access.store.perform {
                try await access.store.add(sample: sample)
                await gate.suspend()
            }
        }
        await gate.waitUntilEntered()
        let context = ModelContext(container)
        let row = SDVersionedHistoryRecord()
        row.envelope = if newerMajor {
            Data(#"{"semantics":{"major":2,"minor":0,"patch":0},"payload":"opaque future shape"}"#
                .utf8)
        } else {
            try JSONEncoder().encode(RecordingControlCodec.encode(
                .source(RecordingAssessmentTestSupport.decision(1)),
                generationID: .initial,
            ))
        }
        context.insert(row)
        try context.save()
        await gate.resume()
        if newerMajor {
            await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
                try await operation.value
            }
            #expect(access.isRevoked)
        } else {
            await #expect(throws: WhereStoreReadConflictError.changedDuringTransaction) {
                try await operation.value
            }
            #expect(!access.isRevoked)
            #expect(try await access.store.allSamples().isEmpty)
        }
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<SDVersionedHistoryRecord>()) == 1)
    }

    @Test func clearingWithinTheIndexedTransactionInvalidatesPriorDeliveries() async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            try await store.add(sample: sample)
            #expect(try await store.allSamples() == [sample])
            let day = try #require(sample.recordingDay?.day)
            try await store.clear(
                in: DateInterval(start: sample.timestamp, duration: 1),
                manualDays: day ... day,
            )
            #expect(try await store.allSamples().isEmpty)
            try await store.add(sample: sample)
            #expect(try await store.allSamples() == [sample])
        }
        #expect(try await store.allSamples() == [sample])
    }

    @Test(arguments: [WhereDataGenerationReason.accountReset, .backupReplace])
    @MainActor func generationRotationErasesVersionedObservationsAndKeepsTheirRequiredMajor(
        reason: WhereDataGenerationReason,
    ) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(VersionedLocationSample.encode(
            sample,
            generationID: .initial,
        ))
        let context = ModelContext(container)
        context.insert(row)
        try context.save()
        _ = try await store.perform {
            try await store.rotateDataGeneration(
                reason: reason,
                changedBy: RecordingControlsTestSupport.device,
                at: Date(),
            )
        }
        #expect(try await store.allSamples().isEmpty)
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<SDVersionedHistoryRecord>()) == 0)
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == 1)
    }
}
