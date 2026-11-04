import Foundation
import PeriscopeCore

/// Moves local share drafts into an admitted history scope. Evidence and its receipt commit
/// together; acknowledgement happens afterward and can be retried without repeating that write.
public actor SharedEvidenceImporter {
    private enum Lifecycle {
        case active
        case resetting(RollbackState)
        case resetComplete
        case retired
    }

    private enum RollbackState {
        case active, resetComplete
    }

    private static let logger = WhereLog.root(SharedEvidenceInboxLog.self)
    private let store: any WhereStore
    private let onCommitted: @Sendable () async -> Void
    private var importTask: Task<Void, any Error>?
    private var lifecycle: Lifecycle = .active

    init(store: any WhereStore, onCommitted: @escaping @Sendable () async -> Void) {
        self.store = store
        self.onCommitted = onCommitted
    }

    public func importPending(from queue: any SharedEvidenceDraftQueuing) async throws {
        switch lifecycle {
            case .active: break
            case .resetting, .resetComplete: return // Keep drafts queued for a new session.
            case .retired: throw DataCompatibilityAccess.AccessError.revoked
        }
        if let importTask { return try await importTask.value }
        let task = Task {
            try await Self.logger.measure(.importDrafts, budget: .seconds(5)) {
                try await self.drain(queue)
            }
        }
        importTask = task
        defer { importTask = nil }
        try await task.value
    }

    /// Close admission before joining any existing import. Reset cannot race a new drain into
    /// the new generation while its post-commit cleanup is still running.
    func pauseForReset() async throws {
        switch lifecycle {
            case .active: lifecycle = .resetting(.active)
            case .resetComplete: lifecycle = .resetting(.resetComplete)
            case .resetting: throw RecordingPersistenceError.recordingRewriteInProgress
            case .retired: throw DataCompatibilityAccess.AccessError.revoked
        }
        // The original caller still receives this task's error. Pausing joins its terminal state.
        _ = await importTask?.result
    }

    func resumeAfterFailedReset() {
        guard case let .resetting(previous) = lifecycle else { return }
        switch previous {
            case .active: lifecycle = .active
            case .resetComplete: lifecycle = .resetComplete
        }
    }

    func finishReset() {
        if case .resetting = lifecycle { lifecycle = .resetComplete }
    }

    func retire() async {
        lifecycle = .retired
        _ = await importTask?.result
    }

    private func drain(_ queue: any SharedEvidenceDraftQueuing) async throws {
        let generation = try await store.dataGeneration().id
        for draftID in try await queue.pendingDraftIDs() {
            // Decode only one attachment batch at a time. A long blocked period must not make
            // the next launch load the entire accumulated inbox before it can make progress.
            guard let draft = try await queue.draft(for: draftID) else { continue }
            let receipt = try draft.receipt()
            let inserted = try await store.perform(expectedDataGenerationID: generation) {
                if let existing = try await store.sharedEvidenceImportReceipt(for: draft.id) {
                    guard existing == receipt else {
                        throw SharedEvidenceDraft.ValidationError.conflictingIdentity
                    }
                    return false
                }
                for item in draft.items {
                    try await store.write(evidence: item.evidence, blob: item.blob)
                }
                try await store.addSharedEvidenceImportReceipt(receipt)
                return true
            }
            if inserted { await onCommitted() }
            try await queue.acknowledge(draft.id)
        }
    }
}
