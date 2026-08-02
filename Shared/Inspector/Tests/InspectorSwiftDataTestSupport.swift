import Foundation
@testable import Inspector
import SwiftData
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
    @Relationship(deleteRule: .nullify, inverse: \TestChild.parent) var children: [TestChild]?

    init(label: String?) {
        self.label = label
        children = []
    }
}

@Model
final class TestChild {
    var name: String?
    var parent: TestParent?

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
func makeContainer() throws -> ModelContainer {
    let schema = Schema([TestWidget.self, TestGadget.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

@MainActor
func seed(_ container: ModelContainer, widgets: Int, gadgets: Int) {
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
    do {
        try context.save()
    } catch {
        Issue.record(error)
    }
}

@MainActor
func makeFamilyContainer() throws -> ModelContainer {
    let schema = Schema([TestParent.self, TestChild.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
