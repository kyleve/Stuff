import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct ModelContextInspectorFetchTests {
    @Test func deletingAnAlreadyMissingRowRemainsIdempotent() throws {
        let container = try makeContainer()
        let insertionContext = container.mainContext
        let widget = TestWidget(
            name: "Removed",
            quantity: 1,
            createdAt: nil,
            isEnabled: true,
            payload: nil,
        )
        insertionContext.insert(widget)
        try insertionContext.save()
        let id = widget.persistentModelID
        insertionContext.delete(widget)
        try insertionContext.save()
        let deletionContext = ModelContext(container)

        #expect(throws: Never.self) {
            try deletionContext.inspectorDelete(TestWidget.self, id: id)
        }
    }
}
