import Foundation
import StorageKit
import Testing

struct StorageSystemTests {
    @Test
    func persistentSystemCreatesItsNamespaceDirectoryUnderTheBase() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))
        #expect(system.url == temp.appending(path: "Where", directoryHint: .isDirectory))
        #expect(FileManager.default.fileExists(atPath: system.url.path))
    }

    @Test
    func vendsTopLevelContainersIdempotently() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))
        let first = try await system.container("user-1")
        let second = try await system.container("user-1")
        #expect(first === second)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
    }

    @Test
    func inMemorySystemRootsInATempDirectoryAndDeleteAllRemovesIt() async throws {
        let system = try StorageSystem("Where", mode: .inMemory)
        let root = system.url
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(root.path.hasPrefix(FileManager.default.temporaryDirectory.path))

        try await system.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test
    func deleteAllRemovesThePersistentNamespaceDirectory() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))
        _ = try await system.container("user-1")
        #expect(FileManager.default.fileExists(atPath: system.url.path))

        try await system.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: system.url.path))
    }

    @Test
    func subdirectoryNamespacesTheSystemUnderTheBase() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem(
            "Where",
            mode: .persistent,
            base: .custom(temp.appending(path: "ns", directoryHint: .isDirectory)),
        )
        #expect(system.url.deletingLastPathComponent().lastPathComponent == "ns")
        #expect(FileManager.default.fileExists(atPath: system.url.path))
    }
}
