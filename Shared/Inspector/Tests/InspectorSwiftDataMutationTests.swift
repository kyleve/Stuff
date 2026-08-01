import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataMutationTests {
    @Test func deletesOneRowAndRefreshesCounts() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        context.insert(MutationRecord(name: "one"))
        context.insert(MutationRecord(name: "two"))
        try context.save()
        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let entity = try #require(model.entities.first { $0.name == "MutationRecord" })
        let row = try #require(try await model.rows(for: entity).rows.first)

        #expect(await model.delete(rowID: row.persistentID, from: entity))
        #expect(model.entities.first { $0.name == entity.name }?.count == 1)
        #expect(model.mutationGeneration == 1)
    }

    @Test func deletesEveryRowOfOneEntityOnly() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        context.insert(MutationRecord(name: "one"))
        context.insert(MutationRecord(name: "two"))
        context.insert(MutationOther(value: 7))
        try context.save()
        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let entity = try #require(model.entities.first { $0.name == "MutationRecord" })

        #expect(await model.deleteAllRows(from: entity))
        #expect(model.entities.first { $0.name == "MutationRecord" }?.count == 0)
        #expect(model.entities.first { $0.name == "MutationOther" }?.count == 1)
    }

    @Test func eraseUsesSupportedAPIAndReopensAnEmptyContainer() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        context.insert(MutationRecord(name: "one"))
        context.insert(MutationOther(value: 7))
        try context.save()
        let configuration = InspectorSwiftDataConfiguration(
            container: container,
            makeContainer: { try Self.makeContainer() },
        )
        let model = InspectorSwiftDataModel(configuration: configuration)
        await model.loadEntities()

        #expect(await model.eraseStore())
        #expect(model.entities.allSatisfy { $0.count == 0 })
        #expect(model.operationError == nil)
    }

    @Test func eraseRemovesConfiguredRecoveryStorage() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "inspector-open-store-erase-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let storeURL = rootURL.appending(path: "database.store")
        let recoveryURL = rootURL.appending(path: "Recovery", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true,
        )
        try Data("pending".utf8).write(to: recoveryURL.appending(path: "journal"))
        let source = InspectorConfiguration.SwiftDataSource(
            id: .init(rawValue: "test"),
            title: "Test",
            storageRootURL: rootURL,
            recoveryStorageURLs: [recoveryURL],
            modelTypes: [MutationRecord.self, MutationOther.self],
            makeContainer: { try Self.makeContainer(at: storeURL) },
        )
        let store = try InspectorSwiftDataStore(source: source)

        _ = try await store.eraseAndReopen()

        #expect(
            FileManager.default.fileExists(atPath: recoveryURL.path(percentEncoded: false))
                == false,
        )
    }

    @Test func cancelledDeletionLeavesTheStoreAndPublishedStateUnchanged() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        context.insert(MutationRecord(name: "kept"))
        try context.save()
        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let entity = try #require(model.entities.first { $0.name == "MutationRecord" })
        let row = try #require(try await model.rows(for: entity).rows.first)

        let deleted = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await model.delete(rowID: row.persistentID, from: entity)
        }.value

        #expect(!deleted)
        #expect(model.entities.first { $0.name == entity.name }?.count == 1)
        #expect(model.mutationGeneration == 0)
    }

    @Test func cancellationAfterEraseStillDiscardsAndReopens() async throws {
        let completedSequence = try await Task {
            var didDiscard = false
            var didReopen = false
            let reopenedValue = try InspectorSwiftDataStore.performEraseAndReopen(
                erase: {
                    withUnsafeCurrentTask { $0?.cancel() }
                },
                discard: {
                    didDiscard = true
                },
                reopen: {
                    didReopen = true
                    return 42
                },
            )
            return reopenedValue == 42 && didDiscard && didReopen
        }.value

        #expect(completedSequence)
    }

    private nonisolated static func makeContainer() throws -> ModelContainer {
        let schema = Schema([MutationRecord.self, MutationOther.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private nonisolated static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema([MutationRecord.self, MutationOther.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none,
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@Model
final class MutationRecord {
    var name: String

    init(name: String) {
        self.name = name
    }
}

@Model
final class MutationOther {
    var value: Int

    init(value: Int) {
        self.value = value
    }
}
