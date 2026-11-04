import Foundation
import Testing
@testable import WhereCore

struct SwiftDataStoreSharedEvidenceTests {
    @Test func receiptsSurviveGenerationRotationAndRollbackTogetherWithEvidence() async throws {
        let store = try SwiftDataStore.inMemory()
        let draft = try makeSharedEvidenceDraft()
        let receipt = try draft.receipt()
        struct Rollback: Error {}
        await #expect(throws: Rollback.self) {
            try await store.perform {
                for item in draft.items {
                    try await store.write(
                        evidence: item.evidence,
                        blob: item.blob,
                    )
                }
                try await store.addSharedEvidenceImportReceipt(receipt)
                throw Rollback()
            }
        }
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.sharedEvidenceImportReceipt(for: draft.id) == nil)
        try await store.perform {
            try await store.addSharedEvidenceImportReceipt(receipt)
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: .init(rawValue: UUID()),
                at: Date(),
            )
        }
        #expect(try await store.sharedEvidenceImportReceipt(for: draft.id) == receipt)
    }
}
