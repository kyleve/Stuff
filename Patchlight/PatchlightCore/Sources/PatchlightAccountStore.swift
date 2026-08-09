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

    public func saveConversation(
        _ conversation: PullRequestConversation,
        refreshedAt: Date,
    ) async throws {
        let payload = try JSONEncoder.patchlight.encode(conversation)
        try await store.upsertConversation(EncryptedConversationRecord(
            pullRequestKey: conversation.pullRequest.id.storageKey,
            payloadCiphertext: cipher.seal(payload),
            refreshedAt: refreshedAt,
        ))
    }

    public func conversation(
        for pullRequest: PullRequestID,
    ) async throws -> StoredConversation? {
        guard let record = try await store.conversation(
            pullRequestKey: pullRequest.storageKey,
        ) else {
            return nil
        }
        do {
            return try StoredConversation(
                value: JSONDecoder().decode(
                    PullRequestConversation.self,
                    from: cipher.open(record.payloadCiphertext),
                ),
                refreshedAt: record.refreshedAt,
            )
        } catch let error as PatchlightVaultError {
            throw error
        } catch {
            throw PatchlightAccountStoreError.invalidConversation
        }
    }

    public func saveViewedDepth(_ viewed: ViewedFileDepth) async throws {
        try await store.upsertViewedDepth(StoredViewedDepth(
            key: viewed.storageKey,
            pullRequestKey: viewed.pullRequest.storageKey,
            path: viewed.path,
            headOID: viewed.headOID.rawValue,
            depthCode: viewed.depth.rawValue,
        ))
    }

    public func viewedDepths(for pullRequest: PullRequestID) async throws -> [ViewedFileDepth] {
        try await store.viewedDepths(pullRequestKey: pullRequest.storageKey).map { value in
            guard let depth = ReviewDepth(rawValue: value.depthCode) else {
                throw PatchlightAccountStoreError.invalidViewedDepth
            }
            return ViewedFileDepth(
                pullRequest: pullRequest,
                path: value.path,
                headOID: GitObjectID(rawValue: value.headOID),
                depth: depth,
            )
        }
    }

    public func saveCorrection(_ correction: ReviewCorrection) async throws {
        try await store.upsertCorrection(StoredCorrection(
            id: correction.id,
            pullRequestKey: correction.pullRequest.storageKey,
            headOID: correction.headOID.rawValue,
            path: correction.path,
            hunkID: correction.hunkID?.rawValue,
            correctionCode: correction.kind.rawValue,
        ))
    }

    public func corrections(
        for pullRequest: PullRequestID,
        headOID: GitObjectID,
    ) async throws -> [ReviewCorrection] {
        try await store.corrections(
            pullRequestKey: pullRequest.storageKey,
            headOID: headOID.rawValue,
        ).map { value in
            guard let kind = ReviewCorrectionKind(rawValue: value.correctionCode) else {
                throw PatchlightAccountStoreError.invalidCorrection
            }
            return ReviewCorrection(
                id: value.id,
                pullRequest: pullRequest,
                headOID: headOID,
                path: value.path,
                hunkID: value.hunkID.map { DiffHunk.ID(rawValue: $0) },
                kind: kind,
            )
        }
    }

    public func removeCorrections(
        for pullRequest: PullRequestID,
        headOID: GitObjectID,
        path: String,
        hunkID: DiffHunk.ID?,
    ) async throws {
        try await store.removeCorrections(
            pullRequestKey: pullRequest.storageKey,
            headOID: headOID.rawValue,
            path: path,
            hunkID: hunkID?.rawValue,
        )
    }

    public func saveRepositorySettings(_ settings: PatchlightRepositorySettings) async throws {
        let encoded = try JSONEncoder.patchlight.encode(settings.overrides)
        try await store.upsertRepositorySettings(StoredRepositorySettings(
            repositoryKey: String(settings.repository.rawValue),
            aiEnabled: settings.aiEnabled,
            imageAIEnabled: settings.imageAIEnabled,
            localOverridesCiphertext: cipher.seal(encoded),
        ))
    }

    public func repositorySettings(
        for repository: RepositoryID,
    ) async throws -> PatchlightRepositorySettings {
        guard let stored = try await store.repositorySettings(
            repositoryKey: String(repository.rawValue),
        ) else {
            return PatchlightRepositorySettings(
                repository: repository,
                aiEnabled: false,
                imageAIEnabled: false,
                overrides: .empty,
            )
        }
        let overrides: PatchlightLocalRepositoryOverrides
        if let payload = stored.localOverridesCiphertext {
            do {
                overrides = try JSONDecoder().decode(
                    PatchlightLocalRepositoryOverrides.self,
                    from: cipher.open(payload),
                )
            } catch let error as PatchlightVaultError {
                throw error
            } catch {
                throw PatchlightAccountStoreError.invalidRepositorySettings
            }
        } else {
            overrides = .empty
        }
        return PatchlightRepositorySettings(
            repository: repository,
            aiEnabled: stored.aiEnabled,
            imageAIEnabled: stored.imageAIEnabled,
            overrides: overrides,
        )
    }
}

public struct StoredConversation: Sendable {
    public let value: PullRequestConversation
    public let refreshedAt: Date

    public init(value: PullRequestConversation, refreshedAt: Date) {
        self.value = value
        self.refreshedAt = refreshedAt
    }
}

public struct ViewedFileDepth: Hashable, Codable, Sendable {
    public let pullRequest: PullRequestID
    public let path: String
    public let headOID: GitObjectID
    public let depth: ReviewDepth

    public init(
        pullRequest: PullRequestID,
        path: String,
        headOID: GitObjectID,
        depth: ReviewDepth,
    ) {
        self.pullRequest = pullRequest
        self.path = path
        self.headOID = headOID
        self.depth = depth
    }

    fileprivate var storageKey: String {
        "\(pullRequest.storageKey):\(path)"
    }
}

public enum PatchlightAccountStoreError: LocalizedError, Equatable, Sendable {
    case invalidDraftText
    case invalidConversation
    case invalidViewedDepth
    case invalidCorrection
    case invalidRepositorySettings

    public var errorDescription: String? {
        switch self {
            case .invalidDraftText:
                "An encrypted draft does not contain valid text."
            case .invalidConversation:
                "An encrypted conversation snapshot is invalid."
            case .invalidViewedDepth:
                "A stored viewed depth has an unknown wire code."
            case .invalidCorrection:
                "A stored review correction has an unknown wire code."
            case .invalidRepositorySettings:
                "Encrypted repository settings are invalid."
        }
    }
}

extension JSONEncoder {
    fileprivate static var patchlight: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
