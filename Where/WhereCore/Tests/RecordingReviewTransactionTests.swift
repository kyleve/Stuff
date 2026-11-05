import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingReviewTransactionTests {
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
