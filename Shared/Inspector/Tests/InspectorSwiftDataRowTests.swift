import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataRowTests {
    @Test func rowsAreFormattedAndTruncatedToRowLimit() async throws {
        let container = try makeContainer()
        seed(container, widgets: 5, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 2),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = try await model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(rowSet.totalCount == 5)
        #expect(rowSet.isTruncated)
        // Each fetched row carries a formatted name cell.
        #expect(rowSet.rows.allSatisfy { $0.cells["name"]?.hasPrefix("Widget") == true })
    }

    @Test func notTruncatedWhenLimitExceedsCount() async throws {
        let container = try makeContainer()
        seed(container, widgets: 2, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 500),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = try await model.rows(for: widget)

        #expect(rowSet.rows.count == 2)
        #expect(!rowSet.isTruncated)
    }

    @Test func defaultFormatHandlesCommonValueKinds() {
        #expect(InspectorSwiftDataStore.defaultFormat("text") == "text")
        #expect(InspectorSwiftDataStore.defaultFormat(true) == "true")
        #expect(InspectorSwiftDataStore.defaultFormat(false) == "false")
        #expect(InspectorSwiftDataStore.defaultFormat(Data(count: 16)) == "16 bytes")

        let uuid = UUID()
        #expect(InspectorSwiftDataStore.defaultFormat(uuid) == uuid.uuidString)
    }

    @Test func defaultFormatUnwrapsOptionalsAndReportsNil() {
        let present: String? = "value"
        let absent: Int? = nil
        #expect(InspectorSwiftDataStore.defaultFormat(present as Any) == "value")
        #expect(InspectorSwiftDataStore.defaultFormat(absent as Any) == "nil")
    }

    @Test func missingColumnsDegradeToAbsentCells() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
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
        let rowSet = try await model.rows(for: entity)
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

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let holder = try #require(model.entities.first { $0.name == "TestBlobHolder" })
        #expect(holder.binaryColumns.contains("blob"))

        let row = try #require(try await model.rows(for: holder).rows.first)
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

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.binaryColumns.contains("payload"))
        let row = try #require(try await model.rows(for: widget).rows.first)
        #expect(row.cells["payload"] == "8 bytes")
    }

    @Test func relationshipColumnRendersAsPlaceholder() async throws {
        let schema = Schema([TestParent.self, TestChild.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(TestParent(label: "P"))
        try context.save()

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let parent = try #require(model.entities.first { $0.name == "TestParent" })
        #expect(parent.relationshipColumns.contains("children"))

        let row = try #require(try await model.rows(for: parent).rows.first)
        #expect(row.cells["children"] == "(relationship)")
        #expect(row.cells["label"] == "P")
    }

    @Test func refreshPicksUpRowsAddedAfterLoad() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        var widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.count == 1)
        #expect(try await model.rows(for: widget).rows.count == 1)

        // New rows written after the first load must show up on refresh, proving
        // each read goes through a fresh context rather than a cached snapshot.
        seed(container, widgets: 2, gadgets: 0)
        await model.loadEntities()
        widget = try #require(model.entities.first { $0.name == "TestWidget" })
        #expect(widget.count == 3)
        #expect(try await model.rows(for: widget).rows.count == 3)
    }

    @Test func columnsIncludeRelationshipNames() async throws {
        let schema = Schema([TestParent.self, TestChild.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
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

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let row = try #require(try await model.rows(for: widget).rows.first)

        #expect(row.cells["isEnabled"] == "true")
        #expect(row.cells["createdAt"]?.isEmpty == false)
    }

    @Test func customValueFormatterOverridesBuiltIn() async throws {
        let container = try makeContainer()
        seed(container, widgets: 1, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container) { value in
                value is Data ? "<blob>" : nil
            },
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rowSet = try await model.rows(for: widget)
        let row = try #require(rowSet.rows.first)

        #expect(row.cells["payload"] == "<blob>")
        // Non-Data values still use the built-in formatting.
        #expect(row.cells["name"] == "Widget 0")
    }
}
