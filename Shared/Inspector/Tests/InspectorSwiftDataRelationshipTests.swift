import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataRelationshipTests {
    @Test func resolvesToManyRelationshipIntoRelatedRows() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        let parent = TestParent(label: "P")
        let children = [TestChild(name: "A"), TestChild(name: "B"), TestChild(name: "C")]
        context.insert(parent)
        for child in children {
            context.insert(child)
        }
        parent.children = children
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let parentEntity = try #require(model.entities.first { $0.name == "TestParent" })
        let parentRow = try #require(try await model.rows(for: parentEntity).rows.first)

        let related = try await model.relatedRows(
            of: parentRow.persistentID,
            relationship: "children",
            sourceType: parentEntity.type,
        )

        #expect(related.isToMany)
        #expect(related.entity?.name == "TestChild")
        #expect(related.rows.count == 3)
        #expect(Set(related.rows.compactMap { $0.cells["name"] }) == ["A", "B", "C"])
        // The drilled-in rows still placeholder their own relationships rather
        // than faulting the graph further.
        #expect(related.entity?.relationshipColumns.contains("parent") == true)
        #expect(related.rows.allSatisfy { $0.cells["parent"] == "(relationship)" })
    }

    @Test func relatedRowsAreCappedToRowLimitButReportTheTrueTotal() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        let parent = TestParent(label: "P")
        context.insert(parent)
        let children = (0 ..< 5).map { TestChild(name: "C\($0)") }
        for child in children {
            context.insert(child)
        }
        parent.children = children
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 2),
        )
        await model.loadEntities()
        let parentEntity = try #require(model.entities.first { $0.name == "TestParent" })
        let parentRow = try #require(try await model.rows(for: parentEntity).rows.first)

        let related = try await model.relatedRows(
            of: parentRow.persistentID,
            relationship: "children",
            sourceType: parentEntity.type,
        )

        #expect(related.isToMany)
        // Capped to rowLimit so a huge to-many can't fault unbounded rows in, but
        // the true count is preserved so the UI can say "showing 2 of 5".
        #expect(related.rows.count == 2)
        #expect(related.totalCount == 5)
        // The batch fetch still materializes the kept rows' attributes.
        #expect(related.rows.allSatisfy { ($0.cells["name"]?.hasPrefix("C")) == true })
    }

    @Test func resolvesToOneRelationshipIntoSingleRow() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        let parent = TestParent(label: "Root")
        let child = TestChild(name: "Solo")
        context.insert(parent)
        context.insert(child)
        child.parent = parent
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let childEntity = try #require(model.entities.first { $0.name == "TestChild" })
        let childRow = try #require(try await model.rows(for: childEntity).rows.first)

        let related = try await model.relatedRows(
            of: childRow.persistentID,
            relationship: "parent",
            sourceType: childEntity.type,
        )

        #expect(!related.isToMany)
        #expect(related.entity?.name == "TestParent")
        #expect(related.rows.count == 1)
        #expect(related.rows.first?.cells["label"] == "Root")
    }

    @Test func nilToOneRelationshipResolvesToNoRows() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        // A child with no parent: the to-one faults to nil, which must degrade to
        // an empty result rather than trapping or inventing a row.
        context.insert(TestChild(name: "Orphan"))
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let childEntity = try #require(model.entities.first { $0.name == "TestChild" })
        let childRow = try #require(try await model.rows(for: childEntity).rows.first)

        let related = try await model.relatedRows(
            of: childRow.persistentID,
            relationship: "parent",
            sourceType: childEntity.type,
        )

        #expect(related.rows.isEmpty)
        #expect(related.entity == nil)
        #expect(related.totalCount == 0)
    }

    @Test func emptyRelationshipResolvesToNoRows() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        context.insert(TestParent(label: "Lonely"))
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let parentEntity = try #require(model.entities.first { $0.name == "TestParent" })
        let parentRow = try #require(try await model.rows(for: parentEntity).rows.first)

        let related = try await model.relatedRows(
            of: parentRow.persistentID,
            relationship: "children",
            sourceType: parentEntity.type,
        )

        #expect(related.rows.isEmpty)
        #expect(related.entity == nil)
    }

    @Test func relationshipResolutionDegradesWhenSourceRowMissing() async throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        let parent = TestParent(label: "P")
        context.insert(parent)
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let parentEntity = try #require(model.entities.first { $0.name == "TestParent" })
        let parentRow = try #require(try await model.rows(for: parentEntity).rows.first)
        let staleID = parentRow.persistentID

        // Delete the row, then resolve against its now-stale id: the predicate
        // fetch finds nothing and the result degrades instead of trapping.
        context.delete(parent)
        try context.save()

        let related = try await model.relatedRows(
            of: staleID,
            relationship: "children",
            sourceType: parentEntity.type,
        )

        #expect(related.rows.isEmpty)
        #expect(related.entity == nil)
    }
}
