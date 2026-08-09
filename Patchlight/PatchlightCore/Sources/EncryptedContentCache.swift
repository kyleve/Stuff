import CryptoKit
import Foundation

public enum CacheCapacity: Int, CaseIterable, Codable, Sendable {
    case oneGB = 1
    case fiveGB = 5
    case tenGB = 10
    case twentyGB = 20

    public static let `default` = CacheCapacity.fiveGB

    var byteCount: Int {
        rawValue * 1_000_000_000
    }
}

public struct CachedObjectID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.count == 64, "A cached object ID must be a SHA-256 digest")
        self.rawValue = rawValue
    }
}

/// An encrypted content-addressed LRU for repository blobs and snapshot images.
public actor EncryptedContentCache {
    private let directory: URL
    private let cipher: VaultCipher
    private let index: any CacheIndexing
    private var maximumByteCount: Int
    private var protectedObjects = Set<CachedObjectID>()

    static func make(
        directory: URL,
        cipher: VaultCipher,
        index: any CacheIndexing,
        capacity: CacheCapacity,
    ) throws -> EncryptedContentCache {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(resourceValues)
        return EncryptedContentCache(
            directory: directory,
            cipher: cipher,
            index: index,
            maximumByteCount: capacity.byteCount,
        )
    }

    private init(
        directory: URL,
        cipher: VaultCipher,
        index: any CacheIndexing,
        maximumByteCount: Int,
    ) {
        self.directory = directory
        self.cipher = cipher
        self.index = index
        self.maximumByteCount = maximumByteCount
    }

    public func insert(_ data: Data) async throws -> CachedObjectID {
        let objectID = CachedObjectID(rawValue: SHA256.hash(data: data).hexString)
        let url = fileURL(for: objectID)
        let ciphertext: Data
        if FileManager.default.fileExists(atPath: url.path) {
            ciphertext = try Data(contentsOf: url)
        } else {
            ciphertext = try cipher.seal(data)
            try ciphertext.write(to: url, options: [.atomic, .completeFileProtection])
        }
        try await index.upsertCacheEntry(CacheIndexEntry(
            objectKey: objectID.rawValue,
            byteCount: ciphertext.count,
            lastAccessed: Date(),
        ))
        try await evictIfNeeded()
        return objectID
    }

    public func data(for objectID: CachedObjectID) async throws -> Data? {
        let url = fileURL(for: objectID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            try await index.removeCacheEntry(objectKey: objectID.rawValue)
            return nil
        }
        let plaintext = try cipher.open(Data(contentsOf: url))
        guard SHA256.hash(data: plaintext).hexString == objectID.rawValue else {
            throw EncryptedContentCacheError.contentAddressMismatch
        }
        let byteCount = try Data(contentsOf: url, options: .mappedIfSafe).count
        try await index.upsertCacheEntry(CacheIndexEntry(
            objectKey: objectID.rawValue,
            byteCount: byteCount,
            lastAccessed: Date(),
        ))
        return plaintext
    }

    /// Objects used by the open workspace are never evicted or cleared.
    public func protect(_ objectIDs: Set<CachedObjectID>) {
        protectedObjects = objectIDs
    }

    public func setCapacity(_ capacity: CacheCapacity) async throws {
        maximumByteCount = capacity.byteCount
        try await evictIfNeeded()
    }

    public func clear() async throws {
        for entry in try await index.cacheEntries() {
            let objectID = CachedObjectID(rawValue: entry.objectKey)
            guard !protectedObjects.contains(objectID) else { continue }
            try removeFileIfPresent(for: objectID)
            try await index.removeCacheEntry(objectKey: entry.objectKey)
        }
    }

    @_spi(Testing)
    public func storedByteCount() async throws -> Int {
        try await index.cacheEntries().reduce(0) { $0 + $1.byteCount }
    }

    @_spi(Testing)
    public func setMaximumByteCount(_ byteCount: Int) async throws {
        precondition(byteCount > 0, "A cache limit must be positive")
        maximumByteCount = byteCount
        try await evictIfNeeded()
    }

    private func evictIfNeeded() async throws {
        let entries = try await index.cacheEntries()
        var storedBytes = entries.reduce(0) { $0 + $1.byteCount }
        guard storedBytes > maximumByteCount else { return }
        for entry in entries.sorted(by: { $0.lastAccessed < $1.lastAccessed }) {
            let objectID = CachedObjectID(rawValue: entry.objectKey)
            guard !protectedObjects.contains(objectID) else { continue }
            try removeFileIfPresent(for: objectID)
            try await index.removeCacheEntry(objectKey: entry.objectKey)
            storedBytes -= entry.byteCount
            if storedBytes <= maximumByteCount { return }
        }
    }

    private func removeFileIfPresent(for objectID: CachedObjectID) throws {
        let url = fileURL(for: objectID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for objectID: CachedObjectID) -> URL {
        directory.appendingPathComponent("\(objectID.rawValue).vault", isDirectory: false)
    }
}

public enum EncryptedContentCacheError: LocalizedError, Equatable, Sendable {
    case contentAddressMismatch

    public var errorDescription: String? {
        "An encrypted cache object does not match its content address."
    }
}

extension SHA256.Digest {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
