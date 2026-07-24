import Foundation
import PortholeCore
import PortholeKit
@testable import PortholeSwiftData
import SwiftData
import Testing

@Model
final class SDConnectorWidget {
    var name: String?
    var quantity: Int?

    init(name: String?, quantity: Int?) {
        self.name = name
        self.quantity = quantity
    }
}

struct SwiftDataConnectorTests {
    private func makeContainer(count: Int) throws -> ModelContainer {
        let schema = Schema([SDConnectorWidget.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        for index in 0 ..< count {
            context.insert(SDConnectorWidget(name: "Widget \(index)", quantity: index))
        }
        try context.save()
        return container
    }

    private func connector(_ container: ModelContainer, rowLimit: Int = 500) -> SwiftDataConnector {
        SwiftDataConnector(
            id: "swiftdata",
            title: "SwiftData",
            container: container,
            modelTypes: nil,
            rowLimit: rowLimit,
        )
    }

    private func source(
        _ connector: SwiftDataConnector,
        _ id: PortholeDataSourceID,
    ) -> PortholeDataSource {
        connector.dataSources().first { $0.descriptor.id == id }!
    }

    @Test func entitiesSourceReportsNameCountAndColumns() async throws {
        let container = try makeContainer(count: 4)
        let page = try await source(connector(container), "entities").fetch(PortholeQuery())
        let widget = try #require(page.rows
            .first { $0["name"]?.stringValue == "SDConnectorWidget" })
        #expect(widget["count"]?.intValue == 4)
        #expect(widget["columns"]?.arrayValue?.contains(.string("name")) == true)
    }

    @Test func rowsSourceReturnsRowsForEntity() async throws {
        let container = try makeContainer(count: 3)
        let page = try await source(connector(container), "rows")
            .fetch(PortholeQuery(filters: ["entity": "SDConnectorWidget"]))
        #expect(page.rows.count == 3)
        #expect(page.totalCount == 3)
        #expect(page.nextCursor == nil)
        #expect(page.rows.contains { $0["name"]?.stringValue == "Widget 0" })
    }

    @Test func rowsSourcePagesWithCursor() async throws {
        let container = try makeContainer(count: 10)
        let rows = source(connector(container, rowLimit: 4), "rows")

        let firstPage = try await rows
            .fetch(PortholeQuery(filters: ["entity": "SDConnectorWidget"]))
        #expect(firstPage.rows.count == 4)
        #expect(firstPage.nextCursor == "2")

        let secondPage = try await rows.fetch(
            PortholeQuery(filters: ["entity": "SDConnectorWidget"], cursor: firstPage.nextCursor),
        )
        #expect(secondPage.rows.count == 4)
        #expect(secondPage.nextCursor == "3")
    }

    @Test func rowsSourceRejectsMissingOrUnknownEntity() async throws {
        let container = try makeContainer(count: 1)
        let rows = source(connector(container), "rows")
        await #expect(throws: PortholeError.self) {
            _ = try await rows.fetch(PortholeQuery())
        }
        await #expect(throws: PortholeError.self) {
            _ = try await rows.fetch(PortholeQuery(filters: ["entity": "Ghost"]))
        }
    }
}
