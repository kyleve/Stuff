import Foundation
import SwiftData
import Testing
@_spi(Testing) import WhereCore

/// Isolated SQLite storage for import scaling and persistent-history tests, without CloudKit.
struct RecordingPersistenceTestSupport {
    let directory: URL
    let container: ModelContainer

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "recording-persistence-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(SwiftDataStore.inspectorModelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appending(path: "Where.store"),
            cloudKitDatabase: .none,
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    func remove() {
        do {
            try container.erase()
            try FileManager.default.removeItem(at: directory)
        } catch { Issue.record("Could not remove temporary recording store: \(error)") }
    }
}
