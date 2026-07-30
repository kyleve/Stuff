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

    private nonisolated static func makeContainer() throws -> ModelContainer {
        let schema = Schema([MutationRecord.self, MutationOther.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
