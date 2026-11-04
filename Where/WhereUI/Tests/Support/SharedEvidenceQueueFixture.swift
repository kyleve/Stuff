import Foundation
import WhereCore

actor SharedEvidenceQueueFixture: SharedEvidenceDraftQueuing {
    struct AcknowledgementFailure: Error {}
    private var drafts: [SharedEvidenceDraft.ID: SharedEvidenceDraft] = [:]
    private var acknowledgementFails = false
    private(set) var reads = 0

    func enqueue(_ draft: SharedEvidenceDraft) {
        drafts[draft.id] = draft
    }

    func pendingDraftIDs() -> [SharedEvidenceDraft.ID] {
        reads += 1; return Array(drafts.keys)
    }

    func draft(for draftID: SharedEvidenceDraft.ID) -> SharedEvidenceDraft? {
        drafts[draftID]
    }

    func acknowledge(_ draftID: SharedEvidenceDraft.ID) throws {
        if acknowledgementFails { throw AcknowledgementFailure() }
        drafts.removeValue(forKey: draftID)
    }

    func failAcknowledgement(_ fails: Bool) {
        acknowledgementFails = fails
    }

    static func draft() throws -> SharedEvidenceDraft {
        try SharedEvidenceDraft(id: .init(rawValue: UUID()), items: [
            .init(evidence: Evidence(
                kind: .document,
                capturedAt: Date(timeIntervalSince1970: 100),
                contentType: .plainText,
            ), blob: Data("shared bytes".utf8)),
        ])
    }
}
