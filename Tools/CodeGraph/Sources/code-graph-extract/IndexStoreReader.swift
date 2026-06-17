import Foundation
import IndexStoreDB

/// Opens an `IndexStoreDB` against a store path and exposes the queries the
/// harvester builds the graph from.
struct IndexStoreReader {
    let db: IndexStoreDB

    init(storePath: String, libIndexStorePath: String) throws {
        guard FileManager.default.fileExists(atPath: storePath) else {
            throw ExtractError.indexStoreNotFound(storePath)
        }
        let library = try IndexStoreLibrary(dylibPath: libIndexStorePath)
        let scratchDB = NSTemporaryDirectory() + "code-graph-extract-db-" + UUID().uuidString
        db = try IndexStoreDB(
            storePath: storePath,
            databasePath: scratchDB,
            library: library,
            waitUntilDoneInitializing: true,
            readonly: false,
            listenToUnitEvents: true,
        )
        db.pollForUnitChangesAndWait(isInitialScan: true)
    }

    /// Re-scan the store for new units (used by `--watch`).
    func refresh() {
        db.pollForUnitChangesAndWait(isInitialScan: false)
    }

    /// Number of distinct symbol names in the store — a cheap sanity signal
    /// that the store opened and is populated.
    func symbolNameCount() -> Int {
        var count = 0
        db.forEachSymbolName { _ in
            count += 1
            return true
        }
        return count
    }
}
