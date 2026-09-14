import Foundation
import PortholeCore
@testable import PortholeRuntime
import Testing

struct PortholeFilesTests {
    @Test func rejectsTraversalAndLinksOutsideTheRoot() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "outside"),
            withDestinationURL: directory.deletingLastPathComponent(),
        )
        let files = PortholeFiles(
            roots: [.init(
                name: .init(rawValue: "root"),
                url: directory,
                excludedPaths: [directory.appending(path: "private")],
            )],
            maximumBytes: 100,
        )
        let scope = PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID())
        for path in ["../other", "outside/other", "private/secret", "/etc/passwd"] {
            let invocation = PortholeInvocation(
                id: UUID(),
                scope: scope,
                capabilityID: .init(rawValue: "read"),
                receiver: nil,
                arguments: .object(["root": .string("root"), "path": .string(path)]),
            )
            #expect(throws: PortholeError.self) { try files.resolve(invocation) }
        }
    }
}
