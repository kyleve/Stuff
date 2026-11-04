import Foundation
@testable import WhereCore

func makeSharedEvidenceDraft() throws -> SharedEvidenceDraft {
    try SharedEvidenceDraft(id: .init(rawValue: UUID()), items: [
        .init(
            evidence: Evidence(
                kind: .document,
                capturedAt: Date(timeIntervalSince1970: 100),
                note: "Shared receipt",
                contentType: .plainText,
            ),
            blob: Data("receipt bytes".utf8),
        ),
        .init(evidence: Evidence(
            kind: .other("Note"),
            capturedAt: Date(timeIntervalSince1970: 100),
            note: "Metadata only",
            contentType: .rawData,
        ), blob: nil),
    ])
}

actor ScriptedSharedEvidenceDraftQueue: SharedEvidenceDraftQueuing {
    enum Event: Equatable {
        case read(SharedEvidenceDraft.ID)
        case acknowledged(SharedEvidenceDraft.ID)
    }

    struct AcknowledgementFailure: Error {}
    private var drafts: [SharedEvidenceDraft.ID: SharedEvidenceDraft] = [:]
    private var acknowledgementFails = false
    private var readGate: CompatibilityTestGate?
    private(set) var events: [Event] = []

    func enqueue(_ draft: SharedEvidenceDraft) throws {
        if let existing = drafts[draft.id], existing != draft {
            throw SharedEvidenceDraft.ValidationError.conflictingIdentity
        }
        drafts[draft.id] = draft
    }

    func pendingDraftIDs() async -> [SharedEvidenceDraft.ID] {
        if let readGate { await readGate.suspend() }
        return Array(drafts.keys)
    }

    func draft(for draftID: SharedEvidenceDraft.ID) -> SharedEvidenceDraft? {
        events.append(.read(draftID))
        return drafts[draftID]
    }

    func acknowledge(_ draftID: SharedEvidenceDraft.ID) throws {
        if acknowledgementFails { throw AcknowledgementFailure() }
        drafts.removeValue(forKey: draftID)
        events.append(.acknowledged(draftID))
    }

    func failAcknowledgement(_ fails: Bool) {
        acknowledgementFails = fails
    }

    func holdRead(_ gate: CompatibilityTestGate?) {
        readGate = gate
    }
}

/// Holds Reset after its store transaction, while installation cleanup is still pending.
actor SharedEvidenceResetOutbox: LocationOutbox {
    let gate: CompatibilityTestGate
    init(gate: CompatibilityTestGate) {
        self.gate = gate
    }

    func load() -> [LocationOutboxEntry] {
        []
    }

    func save(_: [LocationOutboxEntry]) {}
    func clear() async {
        await gate.suspend()
    }
}
