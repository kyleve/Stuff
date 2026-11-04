import Foundation
import Testing
@testable import WhereCore

@MainActor
struct SharedEvidenceImporterTests {
    @Test func eachAttachmentBatchCommitsAndAcknowledgesBeforeTheNextLoads() async throws {
        let store = try SwiftDataStore.inMemory()
        let queue = ScriptedSharedEvidenceDraftQueue()
        let first = try makeSharedEvidenceDraft()
        let second = try makeSharedEvidenceDraft()
        try await queue.enqueue(first)
        try await queue.enqueue(second)
        let importer = SharedEvidenceImporter(store: store, onCommitted: {})
        try await importer.importPending(from: queue)
        let events = await queue.events
        #expect(events.count == 4)
        for index in stride(from: 0, to: events.count, by: 2) {
            guard case let .read(draftID) = events[index] else {
                Issue.record("Expected a draft read after the preceding acknowledgement")
                return
            }
            #expect(events[index + 1] == .acknowledged(draftID))
            #expect(try await store.sharedEvidenceImportReceipt(for: draftID) != nil)
        }
    }

    @Test func resetRollbackReopensOnlyItsOwnPauseAndRetirementRemainsTerminal() async throws {
        let store = try SwiftDataStore.inMemory()
        let queue = ScriptedSharedEvidenceDraftQueue()
        let draft = try makeSharedEvidenceDraft()
        try await queue.enqueue(draft)
        let importer = SharedEvidenceImporter(store: store, onCommitted: {})
        try await importer.pauseForReset()
        await #expect(throws: RecordingPersistenceError.recordingRewriteInProgress) {
            try await importer.pauseForReset()
        }
        try await importer.importPending(from: queue)
        #expect(try await store.allEvidence().isEmpty)
        await importer.resumeAfterFailedReset()
        try await importer.importPending(from: queue)
        #expect(try await store.allEvidence().count == 2)
        try await importer.pauseForReset()
        await importer.retire()
        await importer.resumeAfterFailedReset()
        await #expect(throws: DataCompatibilityAccess.AccessError.revoked) {
            try await importer.importPending(from: queue)
        }
    }

    @Test func acknowledgementRetryNeverRecreatesDeletedEvidence() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: .init(rawValue: "share-fixture")),
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
        let access = try await coordinator.refresh()
        let queue = ScriptedSharedEvidenceDraftQueue()
        let draft = try makeSharedEvidenceDraft()
        try await queue.enqueue(draft)
        await queue.failAcknowledgement(true)
        let importer = SharedEvidenceImporter(store: access.store, onCommitted: {})
        await #expect(throws: ScriptedSharedEvidenceDraftQueue.AcknowledgementFailure.self) {
            try await importer.importPending(from: queue)
        }
        #expect(try await store.allEvidence().count == 2)
        #expect(try await store.evidenceBlob(for: draft.items[0].evidence.id) == draft.items[0]
            .blob)
        #expect(try await store.sharedEvidenceImportReceipt(for: draft.id) == draft.receipt())
        try await store.perform {
            try await store.clear(
                in: DateInterval(start: .distantPast, end: .distantFuture),
                manualDays: CalendarDay(year: 1900, month: 1, day: 1) ...
                    CalendarDay(
                        year: 2100,
                        month: 1,
                        day: 1,
                    ),
            )
        }
        await queue.failAcknowledgement(false)
        // Recreate the importer to model process death after commit but before acknowledgement.
        try await SharedEvidenceImporter(store: access.store, onCommitted: {})
            .importPending(from: queue)
        #expect(try await store.allEvidence().isEmpty)
        #expect(await queue.pendingDraftIDs().isEmpty)
    }

    @Test func retiredScopePreservesPendingBytesForTheNextAdmission() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: .init(rawValue: "share-fixture")),
            policy: .foundation,
            activationReadiness: .pendingValidation,
        )
        let old = try await coordinator.refresh()
        let queue = ScriptedSharedEvidenceDraftQueue()
        let draft = try makeSharedEvidenceDraft()
        try await queue.enqueue(draft)
        let gate = CompatibilityTestGate()
        await queue.holdRead(gate)
        let operation = Task {
            try await SharedEvidenceImporter(store: old.store, onCommitted: {})
                .importPending(from: queue)
        }
        await gate.waitUntilEntered()
        old.revoke()
        await gate.resume()
        await #expect(throws: DataCompatibilityAccess.AccessError.revoked) {
            try await operation.value
        }
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.sharedEvidenceImportReceipt(for: draft.id) == nil)
        await queue.holdRead(nil)
        let next = try await coordinator.refresh()
        try await SharedEvidenceImporter(store: next.store, onCommitted: {})
            .importPending(from: queue)
        #expect(try await store.allEvidence().count == 2)
        #expect(await queue.pendingDraftIDs().isEmpty)
    }

    @Test func resetDuringQueueReadRejectsUnreviewedGeneration() async throws {
        let store = try SwiftDataStore.inMemory()
        let queue = ScriptedSharedEvidenceDraftQueue()
        let draft = try makeSharedEvidenceDraft()
        try await queue.enqueue(draft)
        let gate = CompatibilityTestGate()
        await queue.holdRead(gate)
        let operation = Task {
            try await SharedEvidenceImporter(store: store, onCommitted: {})
                .importPending(from: queue)
        }
        await gate.waitUntilEntered()
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: .init(rawValue: UUID()),
                at: Date(),
            )
        }
        await gate.resume()
        await #expect(throws: (any Error).self) { try await operation.value }
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.sharedEvidenceImportReceipt(for: draft.id) == nil)
        await queue.holdRead(nil)
        #expect(await queue.pendingDraftIDs() == [draft.id])
    }
}
