import Foundation
import SwiftData
import SwiftDataInspector
import Testing

@Model
final class ReaderWidget {
    var name: String?
    var quantity: Int?

    init(name: String?, quantity: Int?) {
        self.name = name
        self.quantity = quantity
    }
}

/// Exercises the promoted, headless public `SwiftDataInspectorReader` API (the
/// non-UI surface the Porthole SwiftData connector uses).
struct SwiftDataInspectorReaderTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ReaderWidget.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seed(_ container: ModelContainer, count: Int) {
        let context = ModelContext(container)
        for index in 0 ..< count {
            context.insert(ReaderWidget(name: "Widget \(index)", quantity: index))
        }
        try? context.save()
    }

    @Test func loadEntitiesReportsNameCountAndColumns() async throws {
        let container = try makeContainer()
        seed(container, count: 5)
        let reader = SwiftDataInspectorReader(
            container: container,
            modelTypes: nil,
            rowLimit: 500,
            valueFormatter: nil,
        )

        let entities = await reader.loadEntities()
        let widget = try #require(entities.first { $0.name == "ReaderWidget" })
        #expect(widget.count == 5)
        #expect(widget.columns.contains("name"))
        #expect(widget.columns.contains("quantity"))
    }

    @Test func rowsReturnFormattedCells() async throws {
        let container = try makeContainer()
        seed(container, count: 3)
        let reader = SwiftDataInspectorReader(
            container: container,
            modelTypes: nil,
            rowLimit: 500,
            valueFormatter: nil,
        )

        let widget = try #require(await reader.loadEntities().first { $0.name == "ReaderWidget" })
        let page = await reader.rows(for: widget)
        #expect(page.rows.count == 3)
        #expect(page.totalCount == 3)
        #expect(page.isTruncated == false)
        #expect(page.rows.contains { $0.cells["name"] == "Widget 0" })
    }

    @Test func rowLimitTruncatesAndPagesGrow() async throws {
        let container = try makeContainer()
        seed(container, count: 10)
        let reader = SwiftDataInspectorReader(
            container: container,
            modelTypes: nil,
            rowLimit: 4,
            valueFormatter: nil,
        )

        let widget = try #require(await reader.loadEntities().first { $0.name == "ReaderWidget" })
        let firstPage = await reader.rows(for: widget, pageCount: 1)
        #expect(firstPage.rows.count == 4)
        #expect(firstPage.totalCount == 10)
        #expect(firstPage.isTruncated)

        let secondPage = await reader.rows(for: widget, pageCount: 2)
        #expect(secondPage.rows.count == 8)
        #expect(secondPage.isTruncated)
    }
}
