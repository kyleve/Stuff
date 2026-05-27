import Foundation

/// Abstraction over the bytes of an evidence attachment. Kept separate from
/// `WhereStore` so blob storage can be swapped (e.g. for files-on-disk,
/// direct iCloud Drive, S3, etc.) without changing the metadata path.
///
/// In the standard CloudKit configuration, `SwiftDataStore` implements both
/// `WhereStore` and `EvidenceBlobStore` and uses `@Attribute(.externalStorage)`
/// so CloudKit chunks blobs as `CKAsset`s.
public protocol EvidenceBlobStore: Sendable {
    func write(blob: Data, for id: UUID) async throws
    func read(for id: UUID) async throws -> Data?
    func delete(for id: UUID) async throws
}

/// Trivial in-memory implementation suitable for tests and SwiftUI previews.
public actor InMemoryEvidenceBlobStore: EvidenceBlobStore {
    private var blobs: [UUID: Data] = [:]

    public init() {}

    public func write(blob: Data, for id: UUID) async throws {
        blobs[id] = blob
    }

    public func read(for id: UUID) async throws -> Data? {
        blobs[id]
    }

    public func delete(for id: UUID) async throws {
        blobs.removeValue(forKey: id)
    }
}
