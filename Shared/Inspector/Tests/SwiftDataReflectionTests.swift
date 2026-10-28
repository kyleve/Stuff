import Foundation
@testable import Inspector
import SwiftData
import Testing

@MainActor
struct SwiftDataReflectionTests {
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
}
