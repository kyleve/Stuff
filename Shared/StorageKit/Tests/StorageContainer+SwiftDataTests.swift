import Foundation
import StorageKit
import SwiftData
import Testing

struct StorageContainerSwiftDataTests {
    @Test func namedStorePinsItsCloudKitPolicyUntilDeleted() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = try StorageSystem("Example", mode: .persistent(base: .custom(root)))
        let shared = try await system.container("shared")
        let first = try await shared.swiftData.modelContainer(
            for: [Note.self],
            named: "history",
            cloudKit: .none,
        )
        let second = try await shared.swiftData.modelContainer(
            for: [Note.self],
            named: "history",
            cloudKit: .none,
        )
        #expect(first === second)
        let expected = shared.url.appending(path: "history/history.store")
        #expect(first.configurations.first?.url.standardizedFileURL == expected.standardizedFileURL)

        await #expect(throws: StorageError.modelStoreConfigurationMismatch("history")) {
            try await shared.swiftData.modelContainer(
                for: [Note.self],
                named: "history",
                cloudKit: .automatic,
            )
        }

        let directory = try await shared.container("history")
        try await directory.deleteContainer()
        let replacement = try await shared.swiftData.modelContainer(
            for: [Note.self],
            named: "history",
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
