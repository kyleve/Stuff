import Foundation
import StorageKit
import Testing

struct BaseDirectoryTests {
    @Test
    func customResolvesToTheGivenURL() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        #expect(try BaseDirectory.custom(temp).resolvedURL() == temp)
    }

    @Test
    func appendsSubdirectoryUnderAStandardDirectory() throws {
        let resolved = try BaseDirectory
            .applicationSupport(subdirectory: "StorageKitTests-namespace")
            .resolvedURL()
        #expect(resolved.lastPathComponent == "StorageKitTests-namespace")
    }

    @Test
    func omittingSubdirectoryReturnsTheStandardDirectory() throws {
        let without = try BaseDirectory.applicationSupport().resolvedURL()
        let with = try BaseDirectory
            .applicationSupport(subdirectory: "child")
            .resolvedURL()
        #expect(with.deletingLastPathComponent().path == without.path)
    }

    @Test
    func doesNotCreateTheSubdirectory() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let resolved = try BaseDirectory.custom(temp).resolvedURL()
        let child = resolved.appending(path: "not-created", directoryHint: .isDirectory)
        // `resolvedURL` only resolves; the system creates the namespace dir.
        #expect(!FileManager.default.fileExists(atPath: child.path))
    }
}
