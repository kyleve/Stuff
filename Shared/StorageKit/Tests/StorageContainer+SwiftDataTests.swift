import Foundation
import StorageKit
import SwiftData
import Testing

struct StorageContainerSwiftDataTests {
    @Test func separateDirectoryAndFileNamePreserveTheExistingLayoutAndCache() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = try StorageSystem("Library", mode: .persistent(base: .custom(root)))
        let library = try await system.container("Stores")
        let first = try await library.swiftData.modelContainer(
            for: [Note.self],
            directory: "Application Support",
            named: "default",
            cloudKit: .none,
        )
        let second = try await library.swiftData.modelContainer(
            for: [Note.self],
            directory: "Application Support",
            named: "default",
            cloudKit: .none,
        )
        #expect(first === second)
        let expected = library.url.appending(path: "Application Support/default.store")
        #expect(first.configurations.first?.url.standardizedFileURL == expected.standardizedFileURL)

        await #expect(throws: StorageError.modelStoreConfigurationMismatch("Application Support")) {
            try await library.swiftData.modelContainer(
                for: [Note.self],
                directory: "Application Support",
                named: "other",
                cloudKit: .none,
            )
        }
        await #expect(throws: StorageError.modelStoreConfigurationMismatch("Application Support")) {
            try await library.swiftData.modelContainer(
                for: [Note.self],
                directory: "Application Support",
                named: "default",
                cloudKit: .automatic,
            )
        }

        let directory = try await library.container("Application Support")
        try await directory.deleteContainer()
        let replacement = try await library.swiftData.modelContainer(
            for: [Note.self],
            directory: "Application Support",
            named: "default",
            cloudKit: .none,
        )
        #expect(replacement !== first)
    }

    @Test func synchronousInMemoryContainersAreIndependentAndDisableCloudKit() throws {
        let first = try SwiftDataStorage.inMemoryModelContainer(for: [Note.self])
        let second = try SwiftDataStorage.inMemoryModelContainer(for: [Note.self])
        #expect(first !== second)
        let configuration = try #require(first.configurations.first)
        #expect(configuration.isStoredInMemoryOnly)
        let context = ModelContext(first)
        context.insert(Note(text: "only in first"))
        try context.save()
        #expect(try ModelContext(second).fetchCount(FetchDescriptor<Note>()) == 0)
    }
}
