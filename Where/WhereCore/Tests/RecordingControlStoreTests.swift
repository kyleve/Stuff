import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingControlStoreTests {
    @Test func duplicateRetryIsIdempotentAndIdentityCollisionRollsBack() async throws {
        let store = try SwiftDataStore.inMemory()
        let controls = RecordingControlStore(
            store: store,
            policy: DataCompatibilityTestSupport.policy,
        )
        let record = try RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(1)),
            generationID: .initial,
        )
        try await controls.append([record], expectedGenerationID: .initial)
        try await controls.append([record], expectedGenerationID: .initial)
        #expect(try await controls.snapshot().records == [record])
        let collision = try RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(1, action: .automatic)),
            generationID: .initial,
        )
        let other = try RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(2)),
            generationID: .initial,
        )
        await #expect(throws: DataCompatibilityError.conflictingRecord) {
            try await controls.append([other, collision], expectedGenerationID: .initial)
        }
        #expect(try await controls.snapshot().records == [record])
    }

    @Test(arguments: [WhereDataGenerationReason.accountReset, .backupReplace])
    func generationRotationRejectsOldWritesAndExplicitImportPreservesIdentityAndBytes(
        reason: WhereDataGenerationReason,
    ) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let controls = RecordingControlStore(
            store: store,
            policy: DataCompatibilityTestSupport.policy,
        )
        let record = try RecordingControlCodec.encode(
            .ignore(RecordingControlsTestSupport.ignore(1)),
            generationID: .initial,
        )
        try await controls.append([record], expectedGenerationID: .initial)
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == nil)
        let generation = try await store.perform {
            try await store.rotateDataGeneration(
                reason: reason,
                changedBy: RecordingControlsTestSupport.device,
                at: Date(),
            )
        }
        #expect(try await controls.snapshot().records.isEmpty)
        #expect(try ModelContext(container)
            .fetchCount(FetchDescriptor<SDVersionedHistoryRecord>()) == 0)
        #expect(try await store.dataCompatibilityState().persistedRequiredMajor == 1)
        await #expect(throws: RecordingPersistenceError.dataGenerationChanged) {
            try await controls.append([record], expectedGenerationID: .initial)
        }
        let imported = record.inGeneration(generation.id)
        try await controls.append([imported], expectedGenerationID: generation.id)
        #expect(try await controls.snapshot().records == [imported])
        #expect(imported.id == record.id)
        #expect(imported.payload == record.payload)
    }

    @Test func revokedPermitCannotCommitPreparedControlsAfterSuspension() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let permit = DataAccessPermit(
            policy: DataCompatibilityTestSupport.policy,
            requiredMajor: 1,
            onCompatibilityFailure: { _ in },
        )
        let scoped = CompatibilityScopedStore(base: store, permit: permit)
        let controls = RecordingControlStore(
            store: scoped,
            policy: DataCompatibilityTestSupport.policy,
        )
        let record = try RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(1)),
            generationID: .initial,
        )
        let gate = CompatibilityTestGate()
        let write = Task {
            try await scoped.perform(expectedDataGenerationID: .initial) {
                try await controls.append([record], expectedGenerationID: .initial)
                await gate.suspend()
            }
        }
        await gate.waitUntilEntered()
        permit.revoke()
        await gate.resume()
        await #expect(throws: DataAccessPermit.AccessError.revoked) { try await write.value }
        #expect(try await store.versionedHistoryRecords(policy: DataCompatibilityTestSupport.policy)
            .isEmpty)
    }
}

extension RecordingControlStoreTests {
    @Test func aNewControlCannotAdoptAnObservationAsItsCausalPredecessor() async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        try await store.perform {
            try await store.raiseRequiredDataMajor(1)
            try await store.add(sample: sample)
        }
        let control = try RecordingControlCodec.encode(
            .source(RecordingAssessmentTestSupport.decision(
                16,
                predecessors: [.init(rawValue: sample.id)],
            )),
            generationID: .initial,
        )
        let controls = RecordingControlStore(
            store: store,
            policy: RecordingBackupTestSupport.policy,
        )
        await #expect(throws: DataCompatibilityError.conflictingRecord) {
            try await controls.append([control], expectedGenerationID: .initial)
        }
        #expect(try await controls.snapshot().records.isEmpty)
        #expect(try await store.allSamples() == [sample])
    }
}
