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

struct EncryptedConversationRecord {
    let pullRequestKey: String
    let payloadCiphertext: Data
    let refreshedAt: Date
}

struct EncryptedAnalysisRecord {
    let cacheKey: String
    let providerCode: String
    let modelID: String
    let payloadCiphertext: Data
    let createdAt: Date
}

struct StoredViewedDepth {
    let key: String
    let pullRequestKey: String
    let path: String
    let headOID: String
    let depthCode: Int
}

struct StoredCorrection {
    let id: UUID
    let pullRequestKey: String
    let headOID: String
    let path: String
    let hunkID: String?
    let correctionCode: String
}

struct StoredRepositorySettings {
    let repositoryKey: String
    let aiEnabled: Bool
    let imageAIEnabled: Bool
    let localOverridesCiphertext: Data?
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

    func upsertConversation(_ conversation: EncryptedConversationRecord) throws {
        let key = conversation.pullRequestKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.ConversationRecord>(
            predicate: #Predicate { $0.pullRequestKey == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.payloadCiphertext = conversation.payloadCiphertext
            record.refreshedAt = conversation.refreshedAt
        } else {
            modelContext.insert(PatchlightSchemaV1.ConversationRecord(
                pullRequestKey: key,
                payloadCiphertext: conversation.payloadCiphertext,
                refreshedAt: conversation.refreshedAt,
            ))
        }
        try modelContext.save()
    }

    func conversation(pullRequestKey: String) throws -> EncryptedConversationRecord? {
        let key = pullRequestKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.ConversationRecord>(
            predicate: #Predicate { $0.pullRequestKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            EncryptedConversationRecord(
                pullRequestKey: $0.pullRequestKey,
                payloadCiphertext: $0.payloadCiphertext,
                refreshedAt: $0.refreshedAt,
            )
        }
    }

    func upsertAnalysis(_ analysis: EncryptedAnalysisRecord) throws {
        let key = analysis.cacheKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.AnalysisRecord>(
            predicate: #Predicate { $0.cacheKey == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.providerCode = analysis.providerCode
            record.modelID = analysis.modelID
            record.payloadCiphertext = analysis.payloadCiphertext
            record.createdAt = analysis.createdAt
        } else {
            modelContext.insert(PatchlightSchemaV1.AnalysisRecord(
                cacheKey: analysis.cacheKey,
                providerCode: analysis.providerCode,
                modelID: analysis.modelID,
                payloadCiphertext: analysis.payloadCiphertext,
                createdAt: analysis.createdAt,
            ))
        }
        try modelContext.save()
    }

    func analysis(cacheKey: String) throws -> EncryptedAnalysisRecord? {
        let key = cacheKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.AnalysisRecord>(
            predicate: #Predicate { $0.cacheKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            EncryptedAnalysisRecord(
                cacheKey: $0.cacheKey,
                providerCode: $0.providerCode,
                modelID: $0.modelID,
                payloadCiphertext: $0.payloadCiphertext,
                createdAt: $0.createdAt,
            )
        }
    }

    func upsertViewedDepth(_ viewed: StoredViewedDepth) throws {
        let key = viewed.key
        var descriptor = FetchDescriptor<PatchlightSchemaV1.ViewedDepthRecord>(
            predicate: #Predicate { $0.key == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.pullRequestKey = viewed.pullRequestKey
            record.path = viewed.path
            record.headOID = viewed.headOID
            record.depthCode = viewed.depthCode
        } else {
            modelContext.insert(PatchlightSchemaV1.ViewedDepthRecord(
                key: viewed.key,
                pullRequestKey: viewed.pullRequestKey,
                path: viewed.path,
                headOID: viewed.headOID,
                depthCode: viewed.depthCode,
            ))
        }
        try modelContext.save()
    }

    func viewedDepths(pullRequestKey: String) throws -> [StoredViewedDepth] {
        let pullRequest = pullRequestKey
        let descriptor = FetchDescriptor<PatchlightSchemaV1.ViewedDepthRecord>(
            predicate: #Predicate { $0.pullRequestKey == pullRequest },
        )
        return try modelContext.fetch(descriptor).map {
            StoredViewedDepth(
                key: $0.key,
                pullRequestKey: $0.pullRequestKey,
                path: $0.path,
                headOID: $0.headOID,
                depthCode: $0.depthCode,
            )
        }
    }

    func upsertCorrection(_ correction: StoredCorrection) throws {
        let id = correction.id
        var descriptor = FetchDescriptor<PatchlightSchemaV1.CorrectionRecord>(
            predicate: #Predicate { $0.id == id },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.pullRequestKey = correction.pullRequestKey
            record.headOID = correction.headOID
            record.path = correction.path
            record.hunkID = correction.hunkID
            record.correctionCode = correction.correctionCode
        } else {
            modelContext.insert(PatchlightSchemaV1.CorrectionRecord(
                id: correction.id,
                pullRequestKey: correction.pullRequestKey,
                headOID: correction.headOID,
                path: correction.path,
                hunkID: correction.hunkID,
                correctionCode: correction.correctionCode,
            ))
        }
        try modelContext.save()
    }

    func corrections(pullRequestKey: String, headOID: String) throws -> [StoredCorrection] {
        let pullRequest = pullRequestKey
        let head = headOID
        let descriptor = FetchDescriptor<PatchlightSchemaV1.CorrectionRecord>(
            predicate: #Predicate {
                $0.pullRequestKey == pullRequest && $0.headOID == head
            },
        )
        return try modelContext.fetch(descriptor).map {
            StoredCorrection(
                id: $0.id,
                pullRequestKey: $0.pullRequestKey,
                headOID: $0.headOID,
                path: $0.path,
                hunkID: $0.hunkID,
                correctionCode: $0.correctionCode,
            )
        }
    }

    func removeCorrections(
        pullRequestKey: String,
        headOID: String,
        path: String,
        hunkID: String?,
    ) throws {
        let pullRequest = pullRequestKey
        let head = headOID
        let filePath = path
        let hunk = hunkID
        try modelContext.delete(
            model: PatchlightSchemaV1.CorrectionRecord.self,
            where: #Predicate {
                $0.pullRequestKey == pullRequest &&
                    $0.headOID == head &&
                    $0.path == filePath &&
                    $0.hunkID == hunk
            },
        )
        try modelContext.save()
    }

    func upsertRepositorySettings(_ settings: StoredRepositorySettings) throws {
        let key = settings.repositoryKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.RepositorySettingsRecord>(
            predicate: #Predicate { $0.repositoryKey == key },
        )
        descriptor.fetchLimit = 1
        if let record = try modelContext.fetch(descriptor).first {
            record.aiEnabled = settings.aiEnabled
            record.imageAIEnabled = settings.imageAIEnabled
            record.localOverridesCiphertext = settings.localOverridesCiphertext
        } else {
            modelContext.insert(PatchlightSchemaV1.RepositorySettingsRecord(
                repositoryKey: key,
                aiEnabled: settings.aiEnabled,
                imageAIEnabled: settings.imageAIEnabled,
                localOverridesCiphertext: settings.localOverridesCiphertext,
            ))
        }
        try modelContext.save()
    }

    func repositorySettings(repositoryKey: String) throws -> StoredRepositorySettings? {
        let key = repositoryKey
        var descriptor = FetchDescriptor<PatchlightSchemaV1.RepositorySettingsRecord>(
            predicate: #Predicate { $0.repositoryKey == key },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map {
            StoredRepositorySettings(
                repositoryKey: $0.repositoryKey,
                aiEnabled: $0.aiEnabled,
                imageAIEnabled: $0.imageAIEnabled,
                localOverridesCiphertext: $0.localOverridesCiphertext,
            )
        }
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
