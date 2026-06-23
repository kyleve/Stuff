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

    @Test func discoversEntitiesFromContainerWithCounts() throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 2)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container),
        )
        model.loadEntities()

        // Sorted by name: TestGadget before TestWidget.
        #expect(model.entities.map(\.name) == ["TestGadget", "TestWidget"])
        let counts = Dictionary(uniqueKeysWithValues: model.entities.map { ($0.name, $0.count) })
        #expect(counts["TestWidget"] == 3)
        #expect(counts["TestGadget"] == 2)
    }

    @Test func explicitModelTypesProduceColumnsAndCounts() throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(
                container: container,
                modelTypes: [TestWidget.self, TestGadget.self],
            ),
        )
        model.loadEntities()

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

    @Test func rowsAreFormattedAndTruncatedToRowLimit() throws {
        let container = try makeContainer()
        seed(container, widgets: 5, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container, rowLimit: 2),
        )
        model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(rowSet.totalCount == 5)
        #expect(rowSet.isTruncated)
        // Each fetched row carries a formatted name cell.
        #expect(rowSet.rows.allSatisfy { $0.cells["name"]?.hasPrefix("Widget") == true })
    }

    @Test func notTruncatedWhenLimitExceedsCount() throws {
        let container = try makeContainer()
        seed(container, widgets: 2, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container, rowLimit: 500),
        )
        model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(!rowSet.isTruncated)
    }

    @Test func defaultFormatHandlesCommonValueKinds() {
        #expect(SwiftDataInspectorModel.defaultFormat("text") == "text")
        #expect(SwiftDataInspectorModel.defaultFormat(true) == "true")
        #expect(SwiftDataInspectorModel.defaultFormat(false) == "false")
        #expect(SwiftDataInspectorModel.defaultFormat(Data(count: 16)) == "16 bytes")

        let uuid = UUID()
        #expect(SwiftDataInspectorModel.defaultFormat(uuid) == uuid.uuidString)
    }

    @Test func defaultFormatUnwrapsOptionalsAndReportsNil() {
        let present: String? = "value"
        let absent: Int? = nil
        #expect(SwiftDataInspectorModel.defaultFormat(present as Any) == "value")
        #expect(SwiftDataInspectorModel.defaultFormat(absent as Any) == "nil")
    }

    @Test func missingColumnsDegradeToAbsentCells() throws {
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
        )
        let rowSet = model.rows(for: entity)
        let row = try #require(rowSet.rows.first)

        #expect(row.cells["name"] == "Widget 0")
        #expect(row.cells["doesNotExist"] == nil)
    }

    @Test func customValueFormatterOverridesBuiltIn() throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = SwiftDataInspectorModel(
            configuration: SwiftDataInspectorConfiguration(container: container) { value in
                value is Data ? "<blob>" : nil
            },
        )
        model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = model.rows(for: widget)
        let row = try #require(rowSet.rows.first)

        #expect(row.cells["payload"] == "<blob>")
        // Non-Data values still use the built-in formatting.
        #expect(row.cells["name"] == "Widget 0")
    }
}
