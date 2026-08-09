import Foundation
import ImageDiffKit

public struct SnapshotImageAsset: Sendable {
    public let oid: GitObjectID
    public let data: Data

    public init(oid: GitObjectID, data: Data) {
        self.oid = oid
        self.data = data
    }
}

public struct SnapshotImagePair: Sendable {
    public let file: DiffFile
    public let base: SnapshotImageAsset?
    public let head: SnapshotImageAsset?
    public let comparison: SnapshotComparison?

    public init(
        file: DiffFile,
        base: SnapshotImageAsset?,
        head: SnapshotImageAsset?,
        comparison: SnapshotComparison?,
    ) {
        self.file = file
        self.base = base
        self.head = head
        self.comparison = comparison
    }
}

public struct SnapshotDimensions: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct SnapshotDiffMetrics: Sendable {
    public let dimensions: SnapshotDimensions
    public let changedPixels: Int
    public let changedFraction: Double
    public let maximumChannelDelta: UInt8
    public let changedBounds: CGRect?

    public init(
        dimensions: SnapshotDimensions,
        changedPixels: Int,
        changedFraction: Double,
        maximumChannelDelta: UInt8,
        changedBounds: CGRect?,
    ) {
        self.dimensions = dimensions
        self.changedPixels = changedPixels
        self.changedFraction = changedFraction
        self.maximumChannelDelta = maximumChannelDelta
        self.changedBounds = changedBounds
    }
}

public enum SnapshotComparison: Sendable {
    case comparable(metrics: SnapshotDiffMetrics, heatmapPNGData: Data?)
    case dimensionMismatch(base: SnapshotDimensions, head: SnapshotDimensions)
}

/// Loads exact snapshot blobs through the encrypted content-addressed cache and
/// performs the authoritative local pixel comparison.
public actor SnapshotWorkspaceCoordinator {
    private let github: any GitHubReading
    private let readCache: PatchlightReadCache
    private let contentCache: EncryptedContentCache
    private let imageDiff = ImageDiffEngine()
    private var protectedObjectIDs = Set<CachedObjectID>()

    public init(
        github: any GitHubReading,
        readCache: PatchlightReadCache,
        contentCache: EncryptedContentCache,
    ) {
        self.github = github
        self.readCache = readCache
        self.contentCache = contentCache
    }

    public func load(
        file: DiffFile,
        repository: RepositoryID,
    ) async throws -> SnapshotImagePair {
        let baseAsset = try await asset(
            repository: repository,
            oid: file.baseBlobOID,
            path: file.previousPath ?? file.path,
        )
        let headAsset = try await asset(
            repository: repository,
            oid: file.headBlobOID,
            path: file.path,
        )
        let comparison: SnapshotComparison? = if let baseAsset, let headAsset {
            try Self.comparison(imageDiff.compare(
                base: baseAsset.data,
                head: headAsset.data,
                options: .exactWithHeatmap,
            ))
        } else {
            nil
        }
        return SnapshotImagePair(
            file: file,
            base: baseAsset,
            head: headAsset,
            comparison: comparison,
        )
    }

    private static func comparison(_ result: ImageDiffResult) -> SnapshotComparison {
        switch result {
            case let .comparable(metrics, heatmapPNGData):
                .comparable(
                    metrics: SnapshotDiffMetrics(
                        dimensions: SnapshotDimensions(
                            width: metrics.dimensions.width,
                            height: metrics.dimensions.height,
                        ),
                        changedPixels: metrics.changedPixels,
                        changedFraction: metrics.changedFraction,
                        maximumChannelDelta: metrics.maximumChannelDelta,
                        changedBounds: metrics.changedBounds,
                    ),
                    heatmapPNGData: heatmapPNGData,
                )
            case let .dimensionMismatch(base, head):
                .dimensionMismatch(
                    base: SnapshotDimensions(width: base.width, height: base.height),
                    head: SnapshotDimensions(width: head.width, height: head.height),
                )
        }
    }

    public func finishWorkspace() async {
        protectedObjectIDs.removeAll()
        await contentCache.protect([])
    }

    private func asset(
        repository: RepositoryID,
        oid: GitObjectID?,
        path: String,
    ) async throws -> SnapshotImageAsset? {
        guard let oid else { return nil }
        let key = ReadSnapshotKey.blob(repository: repository, oid: oid)
        if let stored = try await readCache.load(CachedObjectID.self, key: key),
           let data = try await contentCache.data(for: stored.value)
        {
            await protect(stored.value)
            return SnapshotImageAsset(oid: oid, data: data)
        }
        let data = try await github.blob(repository: repository, oid: oid, path: path)
        let objectID = try await contentCache.insert(data)
        try await readCache.save(
            objectID,
            key: key,
            refreshedAt: Date(),
            etag: nil,
        )
        await protect(objectID)
        return SnapshotImageAsset(oid: oid, data: data)
    }

    private func protect(_ objectID: CachedObjectID) async {
        protectedObjectIDs.insert(objectID)
        await contentCache.protect(protectedObjectIDs)
    }
}
