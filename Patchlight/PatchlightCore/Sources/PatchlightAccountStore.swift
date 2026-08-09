import Foundation

/// Encrypted persistence for user-authored review drafts.
public actor PatchlightAccountStore {
    private let store: PatchlightStore
    private let cipher: VaultCipher

    init(store: PatchlightStore, cipher: VaultCipher) {
        self.store = store
        self.cipher = cipher
    }

    public func saveDraft(_ draft: ReviewDraft) async throws {
        let body = try cipher.seal(Data(draft.body.utf8))
        let anchor = try draft.anchor.map {
            try cipher.seal(JSONEncoder.patchlight.encode($0))
        }
        try await store.upsertDraft(EncryptedDraftRecord(
            id: draft.id,
            pullRequestKey: draft.pullRequest.storageKey,
            path: draft.anchor?.path,
            bodyCiphertext: body,
            anchorCiphertext: anchor,
            updatedAt: draft.updatedAt,
        ))
    }

    public func drafts(for pullRequest: PullRequestID) async throws -> [ReviewDraft] {
        try await store.drafts(pullRequestKey: pullRequest.storageKey).map { record in
            let bodyData = try cipher.open(record.bodyCiphertext)
            guard let body = String(data: bodyData, encoding: .utf8) else {
                throw PatchlightAccountStoreError.invalidDraftText
            }
            let anchor = try record.anchorCiphertext.map {
                try JSONDecoder().decode(DiffAnchor.self, from: cipher.open($0))
            }
            return ReviewDraft(
                id: record.id,
                pullRequest: pullRequest,
                anchor: anchor,
                body: body,
                updatedAt: record.updatedAt,
            )
        }
    }

    public func removeDraft(_ id: UUID) async throws {
        try await store.removeDraft(id: id)
    }
}

public enum PatchlightAccountStoreError: LocalizedError, Equatable, Sendable {
    case invalidDraftText

    public var errorDescription: String? {
        "An encrypted draft does not contain valid text."
    }
}

extension JSONEncoder {
    fileprivate static var patchlight: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
