import Foundation
import PortholeCore
@_spi(Testing) import PortholeKit
import Testing

struct FileBrowserConnectorTests {
    /// Builds a temp tree: `<root>/notes.txt`, `<root>/sub/child.txt`.
    private func makeTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("porthole-files-\(UUID().uuidString)")
        let manager = FileManager.default
        try manager.createDirectory(
            at: root.appendingPathComponent("sub"),
            withIntermediateDirectories: true,
        )
        try Data("hello world".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data("child".utf8).write(to: root.appendingPathComponent("sub/child.txt"))
        return root
    }

    private func connector(root: URL) -> FileBrowserConnector {
        FileBrowserConnector(roots: ["test": root])
    }

    private func source(
        _ connector: FileBrowserConnector,
        _ id: PortholeDataSourceID,
    ) -> PortholeDataSource {
        connector.dataSources().first { $0.descriptor.id == id }!
    }

    private func action(
        _ connector: FileBrowserConnector,
        _ id: PortholeActionID,
    ) -> PortholeAction {
        connector.actions().first { $0.descriptor.id == id }!
    }

    @Test func rootsSourceListsConfiguredRoots() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let page = try await source(connector(root: tree), "roots").fetch(PortholeQuery())
        #expect(page.rows.contains { $0["name"]?.stringValue == "test" })
        #expect(page.rows.first?["exists"]?.boolValue == true)
    }

    @Test func entriesListsDirectoryContents() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let page = try await source(connector(root: tree), "entries")
            .fetch(PortholeQuery(filters: ["root": "test"]))
        let names = Set(page.rows.compactMap { $0["name"]?.stringValue })
        #expect(names == ["notes.txt", "sub"])
        let sub = page.rows.first { $0["name"]?.stringValue == "sub" }
        #expect(sub?["isDirectory"]?.boolValue == true)
    }

    @Test func readFileReturnsContentAndTruncates() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let readFile = action(connector(root: tree), "read-file")

        let full = try await readFile.handler(.object(["root": "test", "path": "notes.txt"]))
        #expect(full["data"]?.dataValue == Data("hello world".utf8))
        #expect(full["truncated"]?.boolValue == false)
        #expect(full["totalSize"]?.intValue == 11)

        let truncated = try await readFile.handler(.object([
            "root": "test",
            "path": "notes.txt",
            "maxBytes": 5,
        ]))
        #expect(truncated["data"]?.dataValue == Data("hello".utf8))
        #expect(truncated["truncated"]?.boolValue == true)
        #expect(truncated["totalSize"]?.intValue == 11)
    }

    @Test func traversalOutsideRootIsRejected() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let readFile = action(connector(root: tree), "read-file")
        await #expect(throws: PortholeError.self) {
            _ = try await readFile.handler(.object(["root": "test", "path": "../../etc/passwd"]))
        }
    }

    @Test func symlinkEscapingRootIsRejected() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        // A symlink inside the root pointing outside it must not be followable.
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("porthole-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: tree.appendingPathComponent("link"),
            withDestinationURL: outside,
        )

        let readFile = action(connector(root: tree), "read-file")
        await #expect(throws: PortholeError.self) {
            _ = try await readFile.handler(.object(["root": "test", "path": "link/secret.txt"]))
        }
    }

    @Test func unknownRootIsRejected() async throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let readFile = action(connector(root: tree), "read-file")
        await #expect(throws: PortholeError.self) {
            _ = try await readFile.handler(.object(["root": "ghost", "path": "notes.txt"]))
        }
    }
}
