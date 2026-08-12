import Foundation
import StuffToolCore
import Testing

struct FileSystemTests {
    @Test func distinguishesKindsAndRoundTripsAtomicData() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        let directory = root.appending(path: "nested", directoryHint: .isDirectory)
        let file = directory.appending(path: "value")
        let copy = directory.appending(path: "copy")
        let moved = directory.appending(path: "moved")
        let link = directory.appending(path: "link")

        #expect(try fileSystem.kind(of: file) == .missing)
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileSystem.setPosixPermissions(0o700, at: directory)
        try fileSystem.write(Data("value".utf8), to: file, atomically: true)

        #expect(try fileSystem.kind(of: directory) == .directory)
        #expect(try fileSystem.kind(of: file) == .file)
        #expect(try fileSystem.read(file) == Data("value".utf8))
        try fileSystem.copyItem(at: file, to: copy)
        try fileSystem.moveItem(at: copy, to: moved)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: moved)
        #expect(try fileSystem.kind(of: copy) == .missing)
        #expect(try fileSystem.read(moved) == Data("value".utf8))
        #expect(try fileSystem.kind(of: link) == .symbolicLink)
        let contents = try fileSystem.contents(of: directory)
        #expect(contents.map(\.lastPathComponent).sorted() == ["link", "moved", "value"])
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int,
        )
        #expect(permissions == 0o700)
    }

    @Test func atomicReplacementPreservesExistingPermissions() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let fileSystem = FoundationFileSystem()
        let file = root.appending(path: "report.md")
        try fileSystem.write(Data("old".utf8), to: file, atomically: false)
        try fileSystem.setPosixPermissions(0o640, at: file)

        try fileSystem.write(Data("new".utf8), to: file, atomically: true)

        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int,
        )
        #expect(try fileSystem.read(file) == Data("new".utf8))
        #expect(permissions == 0o640)
    }
}
