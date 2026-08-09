import Foundation
import SwiftData

struct EncryptedDraftRecord {
    let id: UUID
    let pullRequestKey: String
    let path: String?
    let bodyCiphertext: Data
    let anchorCiphertext: Data?
    let updatedAt: Date
}

struct CacheIndexEntry {
    let objectKey: String
    let byteCount: Int
    let lastAccessed: Date
}

struct EncryptedReadSnapshot {
    let key: String
    let payloadCiphertext: Data
    let refreshedAt: Date
    let etag: String?
}

protocol CacheIndexing: Sendable {
    func cacheEntries() async throws -> [CacheIndexEntry]
    func upsertCacheEntry(_ entry: CacheIndexEntry) async throws
    func removeCacheEntry(objectKey: String) async throws
}

/// Actor-confined access to Patchlight's local-only SwiftData records.
@ModelActor
public actor PatchlightStore: CacheIndexing {
    public enum Storage: Sendable {
        case inMemory
        case onDisk(URL)
    }

    public static var inspectorModelTypes: [any PersistentModel.Type] {
        PatchlightSchemaV1.models
    }

    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(PatchlightSchemaV1.models)
        let configuration = switch storage {
            case .inMemory:
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            case let .onDisk(url):
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: PatchlightMigrationPlan.self,
            configurations: [configuration],
        )
    }

    public static func make(storage: Storage) throws -> PatchlightStore {
        try PatchlightStore(modelContainer: makeContainer(storage: storage))
    }

    func upsertDraft(_ draft: EncryptedDraftRecord) throws {
        let id = draft.id
        var descriptor = FetchDescriptor<PatchlightSchemaV1.DraftRecord>(
            predicate: #Predicate { $0.id == id },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.pullRequestKey = draft.pullRequestKey
            record.path = draft.path
            record.bodyCiphertext = draft.bodyCiphertext
            record.anchorCiphertext = draft.anchorCiphertext
            record.updatedAt = draft.updatedAt
        } else {
            modelContext.insert(PatchlightSchemaV1.DraftRecord(
                id: draft.id,
                pullRequestKey: draft.pullRequestKey,
                path: draft.path,
                bodyCiphertext: draft.bodyCiphertext,
                anchorCiphertext: draft.anchorCiphertext,
                updatedAt: draft.updatedAt,
            ))
        }
        try modelContext.save()
    }

    func drafts(pullRequestKey: String) throws -> [EncryptedDraftRecord] {
        let key = pullRequestKey
        let descriptor = FetchDescriptor<PatchlightSchemaV1.DraftRecord>(
            predicate: #Predicate { $0.pullRequestKey == key },
            sortBy: [SortDescriptor(\.updatedAt)],
        )
        return try modelContext.fetch(descriptor).map {
            EncryptedDraftRecord(
                id: $0.id,
                pullRequestKey: $0.pullRequestKey,
                path: $0.path,
                bodyCiphertext: $0.bodyCiphertext,
                anchorCiphertext: $0.anchorCiphertext,
                updatedAt: $0.updatedAt,
            )
        }
    }

    func removeDraft(id: UUID) throws {
        let draftID = id
        try modelContext.delete(
            model: PatchlightSchemaV1.DraftRecord.self,
            where: #Predicate { $0.id == draftID },
        )
        try modelContext.save()
    }

    func cacheEntries() throws -> [CacheIndexEntry] {
        let descriptor = FetchDescriptor<PatchlightSchemaV1.CacheIndexRecord>(
            sortBy: [SortDescriptor(\.lastAccessed)],
        )
        return try modelContext.fetch(descriptor).map {
            CacheIndexEntry(
                objectKey: $0.objectKey,
                byteCount: $0.byteCount,
                lastAccessed: $0.lastAccessed,
            )
        }
    }

    func upsertCacheEntry(_ entry: CacheIndexEntry) throws {
        let key = entry.objectKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.CacheIndexRecord>(
            predicate: #Predicate { $0.objectKey == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.byteCount = entry.byteCount
            record.lastAccessed = entry.lastAccessed
        } else {
            modelContext.insert(PatchlightSchemaV1.CacheIndexRecord(
                objectKey: entry.objectKey,
                byteCount: entry.byteCount,
                lastAccessed: entry.lastAccessed,
            ))
        }
        try modelContext.save()
    }

    func removeCacheEntry(objectKey: String) throws {
        let key = objectKey
        try modelContext.delete(
            model: PatchlightSchemaV1.CacheIndexRecord.self,
            where: #Predicate { $0.objectKey == key },
        )
        try modelContext.save()
    }

    func upsertReadSnapshot(_ snapshot: EncryptedReadSnapshot) throws {
        let key = snapshot.key
        var descriptor = FetchDescriptor<PatchlightSchemaV1.ReadSnapshotRecord>(
            predicate: #Predicate { $0.key == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.payloadCiphertext = snapshot.payloadCiphertext
            record.refreshedAt = snapshot.refreshedAt
            record.etag = snapshot.etag
        } else {
            modelContext.insert(PatchlightSchemaV1.ReadSnapshotRecord(
                key: snapshot.key,
                payloadCiphertext: snapshot.payloadCiphertext,
                refreshedAt: snapshot.refreshedAt,
                etag: snapshot.etag,
            ))
        }
        try modelContext.save()
    }

    func readSnapshot(key: String) throws -> EncryptedReadSnapshot? {
        let snapshotKey = key
        var descriptor = FetchDescriptor<PatchlightSchemaV1.ReadSnapshotRecord>(
            predicate: #Predicate { $0.key == snapshotKey },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            EncryptedReadSnapshot(
                key: $0.key,
                payloadCiphertext: $0.payloadCiphertext,
                refreshedAt: $0.refreshedAt,
                etag: $0.etag,
            )
        }
    }
}
