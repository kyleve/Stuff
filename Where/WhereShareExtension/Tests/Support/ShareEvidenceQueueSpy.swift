import Foundation
import WhereCore

actor ShareEvidenceQueueSpy: SharedEvidenceDraftQueuing {
    struct UncertainSave: Error {}
    private var drafts: [SharedEvidenceDraft.ID: SharedEvidenceDraft] = [:]
    private var failureAfterSave = false
    private var shouldHold = false
    private var hold: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var attempts: [SharedEvidenceDraft] = []

    func failAfterSaving(_ value: Bool) {
        failureAfterSave = value
    }

    func holdEnqueue() {
        shouldHold = true
    }

    func enqueue(_ draft: SharedEvidenceDraft) async throws {
        attempts.append(draft)
        started?.resume()
        started = nil
        if shouldHold { await withCheckedContinuation { hold = $0 } }
        drafts[draft.id] = draft
        if failureAfterSave { throw UncertainSave() }
    }

    func waitUntilStarted() async {
        guard attempts.isEmpty else { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        shouldHold = false; hold?.resume(); hold = nil
    }

    func pendingDraftIDs() -> [SharedEvidenceDraft.ID] {
        Array(drafts.keys)
    }

    func draft(for draftID: SharedEvidenceDraft.ID) -> SharedEvidenceDraft? {
        drafts[draftID]
    }

    func acknowledge(_ draftID: SharedEvidenceDraft.ID) {
        drafts.removeValue(forKey: draftID)
    }
}
