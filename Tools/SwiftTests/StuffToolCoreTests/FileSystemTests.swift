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

        #expect(fileSystem.kind(of: file) == .missing)
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileSystem.setPosixPermissions(0o700, at: directory)
        try fileSystem.write(Data("value".utf8), to: file, atomically: true)

        #expect(fileSystem.kind(of: directory) == .directory)
        #expect(fileSystem.kind(of: file) == .file)
        #expect(try fileSystem.read(file) == Data("value".utf8))
        try fileSystem.copyItem(at: file, to: copy)
        try fileSystem.moveItem(at: copy, to: moved)
        #expect(fileSystem.kind(of: copy) == .missing)
        #expect(try fileSystem.read(moved) == Data("value".utf8))
        let contents = try fileSystem.contents(of: directory)
        #expect(contents.map(\.lastPathComponent).sorted() == ["moved", "value"])
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int,
        )
        #expect(permissions == 0o700)
    }
}
