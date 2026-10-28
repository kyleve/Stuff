import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct InspectorSwiftDataPaginationTests {
    @Test func growingThePrefixCoversEveryRowInOneConsistentFetch() async throws {
        let container = try makeContainer()
        seed(container, widgets: 5, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container, rowLimit: 2),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })

        // Each page count fetches that many rowLimit-sized pages as one prefix.
        let page1 = try await model.rows(for: widget, pageCount: 1)
        #expect(page1.rows.count == 2)
        #expect(page1.totalCount == 5)
        #expect(page1.isTruncated)
        #expect(Set(page1.rows.map(\.persistentID)).count == 2)

        let page2 = try await model.rows(for: widget, pageCount: 2)
        #expect(page2.rows.count == 4)
        #expect(page2.isTruncated)
        #expect(Set(page2.rows.map(\.persistentID)).count == 4)

        // A big enough prefix returns every row, with no duplicates, and reports
        // that nothing remains — the whole set comes from a single fetch.
        let page3 = try await model.rows(for: widget, pageCount: 3)
        #expect(page3.rows.count == 5)
        #expect(!page3.isTruncated)
        #expect(Set(page3.rows.map(\.persistentID)).count == 5)
    }

    @Test func rowsCarryDistinctPersistentIDs() async throws {
        let container = try makeContainer()
        seed(container, widgets: 3, gadgets: 0)

        let model = InspectorSwiftDataModel(
            configuration: InspectorSwiftDataConfiguration(container: container),
        )
        await model.loadEntities()
        let widget = try #require(model.entities.first { $0.name == "TestWidget" })
        let rows = try await model.rows(for: widget).rows

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.persistentID)).count == 3)
    }
}
