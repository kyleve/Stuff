import Foundation
import WhereCore

public actor FileEvidenceAttachmentRepository: EvidenceAttachmentRepository {
    private let store: JSONFileStore<[EvidenceAttachment]>
    private let seedRecords: [EvidenceAttachment]

    public init(
        fileURL: URL,
        seedRecords: [EvidenceAttachment] = [],
    ) {
        store = JSONFileStore(fileURL: fileURL)
        self.seedRecords = seedRecords
    }

    public func attachments(for manualEntryID: UUID) async -> [EvidenceAttachment] {
        records()
            .filter { $0.manualEntryID == manualEntryID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func attachments(for manualEntryIDs: [UUID]) async -> [EvidenceAttachment] {
        let ids = Set(manualEntryIDs)
        return records()
            .filter { ids.contains($0.manualEntryID) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    public func save(_ attachment: EvidenceAttachment) async {
        await save([attachment])
    }

    public func save(_ attachments: [EvidenceAttachment]) async {
        var merged = Dictionary(uniqueKeysWithValues: records().map { ($0.id, $0) })
        for attachment in attachments {
            merged[attachment.id] = attachment
        }

        let ordered = merged.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.createdAt < rhs.createdAt
        }
        store.save(ordered)
    }

    public func delete(id: UUID) async {
        store.save(records().filter { $0.id != id })
    }

    public func removeAll() async {
        store.save([])
    }

    private func records() -> [EvidenceAttachment] {
        store.load(defaultValue: seedRecords)
    }
}
