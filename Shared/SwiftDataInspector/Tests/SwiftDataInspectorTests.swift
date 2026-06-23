import Foundation
import SwiftData
@testable import SwiftDataInspector
import Testing

@Model
final class TestWidget {
    var name: String?
    var quantity: Int?
    var createdAt: Date?
    var isEnabled: Bool?
    var payload: Data?

    init(
        name: String?,
        quantity: Int?,
        createdAt: Date?,
        isEnabled: Bool?,
        payload: Data?,
    ) {
        self.name = name
        self.quantity = quantity
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.payload = payload
    }
}

@Model
final class TestGadget {
    var label: String?

    init(label: String?) {
        self.label = label
    }
}

@Model
final class TestParent {
    var label: String?
    @Relationship(deleteRule: .nullify) var children: [TestChild]?

    init(label: String?) {
        self.label = label
        children = []
    }
}

@Model
final class TestChild {
    var name: String?

    init(name: String?) {
        self.name = name
    }
}

@Model
final class TestBlobHolder {
    var label: String?
    @Attribute(.externalStorage) var blob: Data?

    init(label: String?, blob: Data?) {
        self.label = label
        self.blob = blob
    }
}

@MainActor
struct SwiftDataInspectorTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([TestWidget.self, TestGadget.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seed(_ container: ModelContainer, widgets: Int, gadgets: Int) {
        let context = container.mainContext
        for index in 0 ..< widgets {
            context.insert(TestWidget(
                name: "Widget \(index)",
                quantity: index,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                isEnabled: index.isMultiple(of: 2),
                payload: Data(count: index),
            ))
        }
        for index in 0 ..< gadgets {
            context.insert(TestGadget(label: "Gadget \(index)"))
        }
        try? context.save()
    }

    // MARK: Entity discovery

    @Test func discoversEntitiesFromContainerWithCounts() async throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 2)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
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

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(
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

    // MARK: Reflection helpers

    @Test func metatypeResolvesFromSchemaEntity() throws {
        let container = try makeContainer()
        let entity = try #require(
            container.schema.entities.first { $0.name == "TestWidget" },
        )
        let type = SwiftDataReflection.metatype(of: entity)
        #expect(type != nil)
        #expect(type.map { String(describing: $0) } == "TestWidget")
    }

    @Test func storedValuesReadsAttributesOfFetchedModel() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1000)
        context.insert(TestWidget(
            name: "Hello",
            quantity: 42,
            createdAt: date,
            isEnabled: true,
            payload: Data(count: 8),
        ))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TestWidget>())
        let model = try #require(fetched.first)
        let values = SwiftDataReflection.storedValues(of: model)

        #expect(values["name"] as? String == "Hello")
        #expect(values["quantity"] as? Int == 42)
        #expect((values["payload"] as? Data)?.count == 8)
    }

    @Test func inspectorCountAndFetchOpenTheExistential() throws {
        let container = try makeContainer()
        seed(container, widgets: 4, gadgets: 0)
        let context = ModelContext(container)

        #expect(context.inspectorCount(of: TestWidget.self) == 4)
        #expect(context.inspectorFetch(TestWidget.self, limit: 2).count == 2)
        #expect(context.inspectorFetch(TestWidget.self, limit: nil).count == 4)
    }

    // MARK: Rows + formatting

    @Test func rowsAreFormattedAndTruncatedToRowLimit() async throws {
        let container = try makeContainer()
        seed(container, widgets: 5, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container, rowLimit: 2),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = await model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(rowSet.totalCount == 5)
        #expect(rowSet.isTruncated)
        // Each fetched row carries a formatted name cell.
        #expect(rowSet.rows.allSatisfy { $0.cells["name"]?.hasPrefix("Widget") == true })
    }

    @Test func notTruncatedWhenLimitExceedsCount() async throws {
        let container = try makeContainer()
        seed(container, widgets: 2, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container, rowLimit: 500),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = await model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(!rowSet.isTruncated)
    }

    @Test func defaultFormatHandlesCommonValueKinds() {
        #expect(SwiftDataInspectorReader.defaultFormat("text") == "text")
        #expect(SwiftDataInspectorReader.defaultFormat(true) == "true")
        #expect(SwiftDataInspectorReader.defaultFormat(false) == "false")
        #expect(SwiftDataInspectorReader.defaultFormat(Data(count: 16)) == "16 bytes")

        let uuid = UUID()
        #expect(SwiftDataInspectorReader.defaultFormat(uuid) == uuid.uuidString)
    }

    @Test func defaultFormatUnwrapsOptionalsAndReportsNil() {
        let present: String? = "value"
        let absent: Int? = nil
        #expect(SwiftDataInspectorReader.defaultFormat(present as Any) == "value")
        #expect(SwiftDataInspectorReader.defaultFormat(absent as Any) == "nil")
    }

    @Test func missingColumnsDegradeToAbsentCells() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        // An entity asking for a column the model has no stored value for: the
        // row simply omits it (the table renders a placeholder) rather than
        // trapping.
        let entity = InspectorEntity(
            name: "TestWidget",
            type: TestWidget.self,
            count: 1,
            columns: ["name", "doesNotExist"],
            binaryColumns: [],
            relationshipColumns: [],
        )
        let rowSet = await model.rows(for: entity)
        let row = try #require(rowSet.rows.first)

        #expect(row.cells["name"] == "Widget 0")
        #expect(row.cells["doesNotExist"] == nil)
    }

    @Test func externalStorageColumnRendersAsPlaceholderWithoutLoading() async throws {
        let schema = Schema([TestBlobHolder.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(TestBlobHolder(label: "x", blob: Data(count: 5000)))
        try context.save()

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        let holder = try #require(model.entities.first { $0.name == "TestBlobHolder" })
        #expect(holder.binaryColumns.contains("blob"))

        let row = try #require(await model.rows(for: holder).rows.first)
        // External-storage blobs are never faulted in: the cell is a bare
        // placeholder, not the byte count and not SwiftData's internal future.
        #expect(row.cells["blob"] == "Data")
        #expect(row.cells["blob"]?.contains("Future") == false)
    }

    @Test func inlineDataColumnRendersAsByteCount() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TestWidget(
            name: "W",
            quantity: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            isEnabled: false,
            payload: Data(count: 8),
        ))
        try context.save()

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.binaryColumns.contains("payload"))
        let row = try #require(await model.rows(for: widget).rows.first)
        #expect(row.cells["payload"] == "8 bytes")
    }

    @Test func relationshipColumnRendersAsPlaceholder() async throws {
        let schema = Schema([TestParent.self, TestChild.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(TestParent(label: "P"))
        try context.save()

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        let parent = try #require(model.entities.first { $0.name == "TestParent" })
        #expect(parent.relationshipColumns.contains("children"))

        let row = try #require(await model.rows(for: parent).rows.first)
        #expect(row.cells["children"] == "(relationship)")
        #expect(row.cells["label"] == "P")
    }

    @Test func refreshPicksUpRowsAddedAfterLoad() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        var widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.count == 1)
        #expect(await model.rows(for: widget).rows.count == 1)

        // New rows written after the first load must show up on refresh, proving
        // each read goes through a fresh context rather than a cached snapshot.
        seed(container, widgets: 2, gadgets: 0)
        await model.loadEntities()
        widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.count == 3)
        #expect(await model.rows(for: widget).rows.count == 3)
    }

    @Test func columnsIncludeRelationshipNames() async throws {
        let schema = Schema([TestParent.self, TestChild.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        let parent = try #require(model.entities.first { $0.name == "TestParent" })
        #expect(parent.columns.contains("label"))
        #expect(parent.columns.contains("children"))
    }

    @Test func extractsDateAndBoolThroughBackingData() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(TestWidget(
            name: "W",
            quantity: 1,
            createdAt: Date(timeIntervalSince1970: 1000),
            isEnabled: true,
            payload: nil,
        ))
        try context.save()

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let row = try #require(await model.rows(for: widget).rows.first)

        #expect(row.cells["isEnabled"] == "true")
        #expect(row.cells["createdAt"]?.isEmpty == false)
    }

    @Test func customValueFormatterOverridesBuiltIn() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container) { value in
                value is Data ? "<blob>" : nil
            },
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = await model.rows(for: widget)
        let row = try #require(rowSet.rows.first)

        #expect(row.cells["payload"] == "<blob>")
        // Non-Data values still use the built-in formatting.
        #expect(row.cells["name"] == "Widget 0")
    }
}
