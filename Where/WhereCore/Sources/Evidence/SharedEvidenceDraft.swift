import CryptoKit
import Foundation

/// Immutable share-sheet input. The extension saves this without opening history or CloudKit.
public struct SharedEvidenceDraft: Codable, Hashable, Sendable {
    public struct ID: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public struct Item: Codable, Hashable, Sendable {
        public let evidence: Evidence
        public let blob: Data?
        public init(evidence: Evidence, blob: Data?) {
            self.evidence = evidence
            self.blob = blob
        }
    }

    /// Stored in the same history transaction as the evidence, outside destructive generations.
    /// It prevents an interrupted queue acknowledgement from resurrecting subsequently deleted
    /// data.
    public struct Receipt: Codable, Hashable, Sendable {
        public let draftID: ID
        public let digest: Data
        public init(draftID: ID, digest: Data) {
            self.draftID = draftID
            self.digest = digest
        }
    }

    public enum ValidationError: Error, Equatable {
        case unsupportedFormat(UInt)
        case emptyDraft
        case duplicateEvidence
        case conflictingIdentity
    }

    public let formatVersion: UInt
    public let id: ID
    public let items: [Item]

    public init(id: ID, items: [Item]) throws {
        formatVersion = 1
        self.id = id
        self.items = items
        try validate()
    }

    public func validate() throws {
        guard formatVersion == 1 else { throw ValidationError.unsupportedFormat(formatVersion) }
        guard !items.isEmpty else { throw ValidationError.emptyDraft }
        guard Set(items.map(\.evidence.id)).count == items.count else {
            throw ValidationError.duplicateEvidence
        }
    }

    public func receipt() throws -> Receipt {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try Receipt(draftID: id, digest: Data(SHA256.hash(data: encoder.encode(self))))
    }
}

/// The share process only enqueues. The admitted application imports and acknowledges drafts.
public protocol SharedEvidenceDraftQueuing: Sendable {
    func enqueue(_ draft: SharedEvidenceDraft) async throws
    func pendingDraftIDs() async throws -> [SharedEvidenceDraft.ID]
    /// Load one draft's bytes. A concurrent successful acknowledgement can remove it first.
    func draft(for draftID: SharedEvidenceDraft.ID) async throws -> SharedEvidenceDraft?
    func acknowledge(_ draftID: SharedEvidenceDraft.ID) async throws
}
