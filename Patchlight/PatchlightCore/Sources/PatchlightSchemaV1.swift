import Foundation
import SwiftData

/// Patchlight's explicit local-only v1 schema. Record classes never leave the
/// model actor; consumers receive immutable Sendable DTOs.
enum PatchlightSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DraftRecord.self,
            AnalysisRecord.self,
            ConversationRecord.self,
            ViewedDepthRecord.self,
            CorrectionRecord.self,
            RepositorySettingsRecord.self,
            CacheIndexRecord.self,
        ]
    }

    @Model
    final class DraftRecord {
        #Index<DraftRecord>([\.pullRequestKey], [\.updatedAt])

        @Attribute(.unique) var id: UUID
        var pullRequestKey: String
        var path: String?
        var bodyCiphertext: Data
        var anchorCiphertext: Data?
        var updatedAt: Date

        init(
            id: UUID,
            pullRequestKey: String,
            path: String?,
            bodyCiphertext: Data,
            anchorCiphertext: Data?,
            updatedAt: Date,
        ) {
            self.id = id
            self.pullRequestKey = pullRequestKey
            self.path = path
            self.bodyCiphertext = bodyCiphertext
            self.anchorCiphertext = anchorCiphertext
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class AnalysisRecord {
        @Attribute(.unique) var cacheKey: String
        var providerCode: String
        var modelID: String
        var payloadCiphertext: Data
        var createdAt: Date

        init(
            cacheKey: String,
            providerCode: String,
            modelID: String,
            payloadCiphertext: Data,
            createdAt: Date,
        ) {
            self.cacheKey = cacheKey
            self.providerCode = providerCode
            self.modelID = modelID
            self.payloadCiphertext = payloadCiphertext
            self.createdAt = createdAt
        }
    }

    @Model
    final class ConversationRecord {
        @Attribute(.unique) var pullRequestKey: String
        var payloadCiphertext: Data
        var refreshedAt: Date

        init(pullRequestKey: String, payloadCiphertext: Data, refreshedAt: Date) {
            self.pullRequestKey = pullRequestKey
            self.payloadCiphertext = payloadCiphertext
            self.refreshedAt = refreshedAt
        }
    }

    @Model
    final class ViewedDepthRecord {
        @Attribute(.unique) var key: String
        var pullRequestKey: String
        var path: String
        var headOID: String
        /// Stable numeric wire code from `ReviewDepth`, never a Swift case name.
        var depthCode: Int

        init(
            key: String,
            pullRequestKey: String,
            path: String,
            headOID: String,
            depthCode: Int,
        ) {
            self.key = key
            self.pullRequestKey = pullRequestKey
            self.path = path
            self.headOID = headOID
            self.depthCode = depthCode
        }
    }

    @Model
    final class CorrectionRecord {
        #Index<CorrectionRecord>([\.headOID], [\.pullRequestKey])

        @Attribute(.unique) var id: UUID
        var pullRequestKey: String
        var headOID: String
        var path: String
        var hunkID: String?
        /// `S` = always show, `M` = mechanical.
        var correctionCode: String

        init(
            id: UUID,
            pullRequestKey: String,
            headOID: String,
            path: String,
            hunkID: String?,
            correctionCode: String,
        ) {
            self.id = id
            self.pullRequestKey = pullRequestKey
            self.headOID = headOID
            self.path = path
            self.hunkID = hunkID
            self.correctionCode = correctionCode
        }
    }

    @Model
    final class RepositorySettingsRecord {
        @Attribute(.unique) var repositoryKey: String
        var aiEnabled: Bool
        var imageAIEnabled: Bool
        var localOverridesCiphertext: Data?

        init(
            repositoryKey: String,
            aiEnabled: Bool,
            imageAIEnabled: Bool,
            localOverridesCiphertext: Data?,
        ) {
            self.repositoryKey = repositoryKey
            self.aiEnabled = aiEnabled
            self.imageAIEnabled = imageAIEnabled
            self.localOverridesCiphertext = localOverridesCiphertext
        }
    }

    @Model
    final class CacheIndexRecord {
        #Index<CacheIndexRecord>([\.lastAccessed])

        @Attribute(.unique) var objectKey: String
        var byteCount: Int
        var lastAccessed: Date

        init(objectKey: String, byteCount: Int, lastAccessed: Date) {
            self.objectKey = objectKey
            self.byteCount = byteCount
            self.lastAccessed = lastAccessed
        }
    }
}

enum PatchlightMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PatchlightSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
