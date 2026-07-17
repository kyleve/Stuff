import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct LedgerConfigStoreTests {
    /// A store in a unique temp directory that never touches the user's real
    /// Application Support.
    private func makeStore() -> (store: LedgerConfigStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgerConfigStoreTests-\(UUID().uuidString)")
        return (LedgerConfigStore(directory: directory), directory)
    }

    @Test func missingFileLoadsAsInitial() throws {
        let (store, _) = makeStore()
        #expect(try store.load() == .initial)
    }

    @Test func roundTripsAConfiguration() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = LedgerConfiguration(
            teamMemberEmail: "me@company.com",
            refreshInterval: 300,
        )
        try store.save(configuration)
        #expect(try store.load() == configuration)
    }

    @Test func corruptFileThrowsRatherThanResetting() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("configuration.json"))

        #expect(throws: (any Error).self) { try store.load() }
    }
}
