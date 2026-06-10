import Foundation
import Testing
@testable import WhereCore

/// Exercises the one-time legacy-store move that backs the App Group
/// relocation (see `SwiftDataStore.relocateLegacyStore(from:to:)`), using
/// plain marker files in temp directories so no real SwiftData store is
/// involved.
struct StoreRelocationTests {
    private let root: URL
    private let legacyDirectory: URL
    private let destinationDirectory: URL

    private var legacyStore: URL {
        legacyDirectory.appending(path: "default.store")
    }

    private var destinationStore: URL {
        destinationDirectory.appending(path: "default.store")
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "StoreRelocationTests-\(UUID().uuidString)")
        legacyDirectory = root.appending(path: "legacy")
        destinationDirectory = root.appending(path: "group/Library/Application Support")
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true,
        )
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(content.utf8).write(to: url)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test func movesStoreSidecarsAndExternalStorage() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("store", to: legacyStore)
        try write("shm", to: legacyDirectory.appending(path: "default.store-shm"))
        try write("wal", to: legacyDirectory.appending(path: "default.store-wal"))
        let blobPath = ".default_SUPPORT/_EXTERNAL_DATA/blob"
        try write("blob", to: legacyDirectory.appending(path: blobPath))

        try SwiftDataStore.relocateLegacyStore(from: legacyStore, to: destinationStore)

        #expect(try contents(of: destinationStore) == "store")
        #expect(
            try contents(of: destinationDirectory.appending(path: "default.store-shm")) == "shm",
        )
        #expect(
            try contents(of: destinationDirectory.appending(path: "default.store-wal")) == "wal",
        )
        #expect(try contents(of: destinationDirectory.appending(path: blobPath)) == "blob")
        // Moved, not copied: nothing of the store remains at the old paths.
        #expect(!FileManager.default.fileExists(atPath: legacyStore.path))
        #expect(
            !FileManager.default
                .fileExists(atPath: legacyDirectory.appending(path: ".default_SUPPORT").path),
        )
    }

    @Test func movesBareStoreWithoutSidecars() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("store", to: legacyStore)

        try SwiftDataStore.relocateLegacyStore(from: legacyStore, to: destinationStore)

        #expect(try contents(of: destinationStore) == "store")
        #expect(!FileManager.default.fileExists(atPath: legacyStore.path))
    }

    @Test func noOpWhenLegacyStoreMissing() throws {
        defer { try? FileManager.default.removeItem(at: root) }

        try SwiftDataStore.relocateLegacyStore(from: legacyStore, to: destinationStore)

        #expect(!FileManager.default.fileExists(atPath: destinationStore.path))
    }

    @Test func neverClobbersAnExistingDestinationStore() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try write("stale legacy", to: legacyStore)
        try write("current", to: destinationStore)

        try SwiftDataStore.relocateLegacyStore(from: legacyStore, to: destinationStore)

        // Destination untouched, legacy left in place.
        #expect(try contents(of: destinationStore) == "current")
        #expect(try contents(of: legacyStore) == "stale legacy")
    }
}
