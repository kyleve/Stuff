import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataEntityTests {
    @Test func discoversEntitiesFromContainerWithCounts() async throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 2)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()

        // Sorted by name: TestGadget before TestWidget.
        #expect(model.entities.map(\.name) == ["TestGadget", "TestWidget"])
        let counts = Dictionary(uniqueKeysWithValues: model.entities.map { ($0.name, $0.count) })
        #expect(counts["TestWidget"] == 3)
        #expect(counts["TestGadget"] == 2)
    }

    @Test func explicitModelTypesProduceColumnsAndCounts() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(
                container: container,
                modelTypes: [TestWidget.self, TestGadget.self],
            ),
        )
        await model.loadEntities()

        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.count == 1)
        #expect(widget.columns.contains("name"))
        #expect(widget.columns.contains("quantity"))
        #expect(widget.columns.contains("payload"))
    }

    @Test func discoversEntitiesWhenModelTypesNilReflectsSchema() async throws {
        let container = try makeContainer()
        seed(container, widgets: 2, gadgets: 1)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(
                container: container,
                modelTypes: nil,
            ),
        )
        await model.loadEntities()

        #expect(model.entities.map(\.name) == ["TestGadget", "TestWidget"])
    }

    @Test func emptyModelTypesListShowsNoEntities() async throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 2)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(
                container: container,
                modelTypes: [],
            ),
        )
        await model.loadEntities()

        #expect(model.entities.isEmpty)
    }

    @Test func destinationTypeComesFromSchemaRelationship() throws {
        let container = try makeFamilyContainer()
        let type = SwiftDataReflection.destinationType(
            of: TestChild.self,
            relationshipNamed: "parent",
            in: container.schema,
        )
        #expect(type != nil)
        #expect(type.map { String(describing: $0) } == "TestParent")
    }

    @Test func columnCharacterCountsTrackLongestCellPerColumn() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TestWidget(
            name: "Short",
            quantity: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            isEnabled: false,
            payload: nil,
        ))
        context.insert(TestWidget(
            name: "A much longer widget name",
            quantity: 2,
            createdAt: Date(timeIntervalSince1970: 1),
            isEnabled: true,
            payload: nil,
        ))
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = try await model.rows(for: widget)

        #expect(rowSet.columnCharacterCounts["name"] == "A much longer widget name".count)
    }

    @Test func inspectorModelsBatchFetchesRowsByID() throws {
        let container = try makeFamilyContainer()
        let context = container.mainContext
        let parent = TestParent(label: "P")
        let children = [TestChild(name: "A"), TestChild(name: "B")]
        context.insert(parent)
        for child in children {
            context.insert(child)
        }
        parent.children = children
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TestChild>())
        let ids = fetched.map(\.persistentModelID)
        let readContext = ModelContext(container)
        let byID = readContext.inspectorModels(TestChild.self, ids: ids)

        #expect(byID.count == 2)
        #expect(Set(byID.keys) == Set(ids))
        #expect(Set(byID.values
                .compactMap { SwiftDataReflection.storedValues(of: $0)["name"] as? String }) == [
            "A",
            "B",
        ])
    }

    @Test func binaryDescriptionReportsInlineBytesOrPlaceholder() {
        #expect(InspectorSwiftDataStore.binaryDescription(Data(count: 12)) == "12 bytes")
        #expect(InspectorSwiftDataStore.binaryDescription("not data") == "Data")
        #expect(InspectorSwiftDataStore.binaryDescription(Data?.none as Any) == "Data")
    }

    @Test func defaultFormatUsesNumericDateStyle() throws {
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15
        components.hour = 14
        components.minute = 30
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(from: components))
        let formatted = InspectorSwiftDataStore.defaultFormat(date)
        #expect(formatted.contains("2024"))
        #expect(formatted.contains("6"))
        #expect(formatted.contains("15"))
    }

    @Test func skipsCountWhenFetchProvesNoTruncation() async throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 10),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = try await model.rows(for: widget)

        #expect(rowSet.rows.count == 3)
        #expect(rowSet.totalCount == 3)
        #expect(!rowSet.isTruncated)
    }
}
