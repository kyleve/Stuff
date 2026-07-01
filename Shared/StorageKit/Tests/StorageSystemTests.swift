import Foundation
import StorageKit
import Testing

struct StorageSystemTests {
    @Test
    func persistentSystemCreatesItsNamespaceDirectoryUnderTheBase() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem("Where", mode: .persistent(base: .custom(temp)))
        #expect(system.url == temp.appending(path: "Where", directoryHint: .isDirectory))
        #expect(FileManager.default.fileExists(atPath: system.url.path))
    }

    @Test
    func vendsTopLevelContainersIdempotently() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem("Where", mode: .persistent(base: .custom(temp)))
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

        let system = try StorageSystem("Where", mode: .persistent(base: .custom(temp)))
        _ = try await system.container("user-1")
        #expect(FileManager.default.fileExists(atPath: system.url.path))

        try await system.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: system.url.path))
    }

    @Test
    func sameNamedSystemsWithDifferentBasesHaveIndependentKeyValueStores() async throws {
        let tempA = try makeTemporaryDirectory()
        let tempB = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempA)
            try? FileManager.default.removeItem(at: tempB)
        }

        let systemA = try StorageSystem("Where", mode: .persistent(base: .custom(tempA)))
        let systemB = try StorageSystem("Where", mode: .persistent(base: .custom(tempB)))
        let userA = try await systemA.container("user-1")
        let userB = try await systemB.container("user-1")

        await userA.keyValueStore().set(99, forKey: "count")

        // Same logical key path, different base: the suites must not collide.
        #expect(await userA.keyValueStore().integer(forKey: "count") == 99)
        #expect(await userB.keyValueStore().integer(forKey: "count") == 0)

        try await systemA.deleteAll()
        try await systemB.deleteAll()
    }

    @Test
    func subdirectoryNamespacesTheSystemUnderTheBase() throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }

        let system = try StorageSystem(
            "Where",
            mode: .persistent(
                base: .custom(temp.appending(path: "ns", directoryHint: .isDirectory)),
            ),
        )
        #expect(system.url.deletingLastPathComponent().lastPathComponent == "ns")
        #expect(FileManager.default.fileExists(atPath: system.url.path))
    }
}
