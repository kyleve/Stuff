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

        #expect(fileSystem.kind(of: file) == .missing)
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileSystem.setPosixPermissions(0o700, at: directory)
        try fileSystem.write(Data("value".utf8), to: file, atomically: true)

        #expect(fileSystem.kind(of: directory) == .directory)
        #expect(fileSystem.kind(of: file) == .file)
        #expect(try fileSystem.read(file) == Data("value".utf8))
        let contents = try fileSystem.contents(of: directory)
        #expect(contents.count == 1)
        #expect(contents[0].lastPathComponent == "value")
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int,
        )
        #expect(permissions == 0o700)
    }
}
