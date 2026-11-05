import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingReviewTransactionTests {
    @Test func futurePlaceImportDuringSaveInvalidatesTheEntireOngoingProposal() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let importer = SwiftDataStore(modelContainer: container)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(.place(
            placeID: RecordingControlsTestSupport.placeID,
            validity: [.init(start: RecordingAssessmentTestSupport.time(0), end: nil)],
            action: .set(kind: .regularHome, coordinate: .init(latitude: 37, longitude: -122)),
        ))
        let record = try RecordingControlCodec.encode(
            RecordingControlEditTestSupport.control(proposal),
            generationID: proposal.evidence.generationID,
        )
        let future = try RecordingControlsTestSupport.place(
            30,
            start: 1e8,
            end: nil,
            action: .remove,
        )
        let gate = CompatibilityTestGate()
        var configured = RecordingReviewTransaction(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        )
        configured.beforeWrite = { await gate.suspend() }
        let transaction = configured
        let operation = Task { try await transaction.apply(record, reviewed: proposal.evidence) }
        await gate.waitUntilEntered()
        try await RecordingChoiceTestSupport.append(.place(future), store: importer)
        await gate.resume()
        guard case let .changed(current) = try await operation.value
        else { Issue.record("The future import must require a new preview before save"); return }
        #expect(current.controls.places == [future])
        #expect(current.query == proposal.evidence.query)
        let saved = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(saved.count == 1)
        #expect(saved.first?.id != record.id)
    }

    @Test func revocationDuringSaveRejectsEveryRecordInTheBatch() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let access = DataCompatibilityAccess(
            base: store,
            identity: .local(storeID: DataCompatibilityTestSupport.storeID),
            requiredMajor: 1,
            policy: RecordingChoiceTestSupport.policy,
            onFailure: { _, _ in },
        )
        let coordinator = RecordingControlEditTestSupport.coordinator(store: access.store)
        let proposal = try await coordinator
            .review(RecordingControlEditTestSupport.calendarRecovery().edits)
        let records = try proposal.edits.map {
            try RecordingControlCodec.encode(
                $0.control,
                generationID: proposal.evidence.generationID,
            )
        }
        let gate = CompatibilityTestGate()
        var configured = RecordingReviewTransaction(
            store: access.store,
            policy: RecordingChoiceTestSupport.policy,
        )
        configured.beforeWrite = { await gate.suspend() }
        let transaction = configured
        let operation = Task { try await transaction.apply(records, reviewed: proposal.evidence) }
        await gate.waitUntilEntered()
        access.revoke()
        await gate.resume()
        await #expect(throws: DataAccessPermit.AccessError.revoked) { try await operation.value }
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
    }

    @Test func repeatedUnrelatedImportsStopAfterTheBoundAndRetainTheOriginalProposal() async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let store = SwiftDataStore(modelContainer: container)
        let importer = SwiftDataStore(modelContainer: container)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let proposal = try await RecordingChoiceTestSupport
            .proposal(coordinator.review(RecordingChoiceTestSupport.request()))
        let record = try RecordingControlCodec.encode(
            .source(proposal.decision),
            generationID: proposal.evidence.generationID,
        )
        let attempts = RecordingChoiceTestSupport.Commits()
        var transaction = RecordingReviewTransaction(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        )
        transaction.beforeWrite = {
            await attempts.record()
            do {
                try await importer.perform {
                    try await importer.restoreHomeRegionRecord(.init(
                        id: UUID(),
                        region: .california,
                        updatedAt: Date(),
                    ))
                }
            } catch { Issue.record(error) }
        }
        let prepared = transaction
        await #expect(throws: WhereStoreReadConflictError.changedDuringTransaction) {
            try await prepared.apply(record, reviewed: proposal.evidence)
        }
        #expect(await attempts.count == 3)
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)
        #expect(try await coordinator.apply(proposal) == .applied)
        let records = try await store
            .versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
        #expect(records == [record])
    }
}
