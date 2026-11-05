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
