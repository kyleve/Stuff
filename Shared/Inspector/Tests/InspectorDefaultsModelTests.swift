import Foundation
@testable import Inspector
import Testing

@MainActor
struct InspectorDefaultsModelTests {
    @Test func enumeratesOnlyTheConfiguredPersistentDomain() throws {
        let fixture = try DefaultsDomainFixture()
        defer { fixture.cleanup() }
        fixture.defaults.register(defaults: ["registered": "excluded"])
        let globalKey = "inspector-global-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: globalKey) }
        UserDefaults.standard.set("global", forKey: globalKey)
        fixture.defaults.set("included", forKey: "persisted")

        let model = InspectorDefaultsModel(domain: fixture.domain)

        #expect(model.entries.map(\.key) == ["persisted"])
    }

    @Test func recognizesEditableScalarTypesAndReadOnlyComplexValues() throws {
        let fixture = try DefaultsDomainFixture()
        defer { fixture.cleanup() }
        let date = Date(timeIntervalSinceReferenceDate: 123)
        let url = try #require(URL(string: "https://example.com/inspector"))
        fixture.defaults.set("text", forKey: "string")
        fixture.defaults.set(true, forKey: "bool")
        fixture.defaults.set(42, forKey: "integer")
        fixture.defaults.set(4.5, forKey: "double")
        fixture.defaults.set(date, forKey: "date")
        fixture.defaults.set(url, forKey: "url")
        fixture.defaults.set(["one", "two"], forKey: "array")
        fixture.defaults.set(["key": "value"], forKey: "dictionary")
        fixture.defaults.set(Data([1, 2, 3]), forKey: "data")

        let entries = Dictionary(
            uniqueKeysWithValues: InspectorDefaultsModel(domain: fixture.domain)
                .entries.map { ($0.key, $0.value) },
        )

        #expect(entries["string"] == .string("text"))
        #expect(entries["bool"] == .boolean(true))
        #expect(entries["integer"] == .integer(42))
        #expect(entries["double"] == .floatingPoint(4.5))
        #expect(entries["date"] == .date(date))
        #expect(entries["url"] == .url(url))
        #expect(entries["array"]?.isEditable == false)
        #expect(entries["dictionary"]?.isEditable == false)
        #expect(entries["data"]?.isEditable == false)
    }

    @Test func editsScalarsWithoutChangingTheirTypes() throws {
        let fixture = try DefaultsDomainFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(1, forKey: "integer")
        fixture.defaults.set("old", forKey: "string")
        let model = InspectorDefaultsModel(domain: fixture.domain)

        #expect(model.save(.integer(9), forKey: "integer"))
        #expect(model.save(.string("new"), forKey: "string"))
        #expect(model.entries.first { $0.key == "integer" }?.value == .integer(9))
        #expect(model.entries.first { $0.key == "string" }?.value == .string("new"))
        #expect(
            fixture.defaults.persistentDomain(forName: fixture.suiteName)?["integer"]
                is NSNumber,
        )
        #expect(
            fixture.defaults.persistentDomain(forName: fixture.suiteName)?["string"]
                is String,
        )
    }

    @Test func refusesComplexEditsAndDeletesIndividualValues() throws {
        let fixture = try DefaultsDomainFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(["value"], forKey: "complex")
        fixture.defaults.set("remove", forKey: "individual")
        let model = InspectorDefaultsModel(domain: fixture.domain)

        #expect(!model.save(.complex(summary: "Array"), forKey: "complex"))
        #expect(model.errorMessage != nil)
        #expect(model.delete(key: "individual"))
        #expect(fixture.defaults.object(forKey: "individual") == nil)
        #expect(fixture.defaults.object(forKey: "complex") != nil)
    }
}

private struct DefaultsDomainFixture {
    let suiteName: String
    let defaults: UserDefaults
    let domain: InspectorConfiguration.DefaultsDomain

    init() throws {
        suiteName = "inspector.defaults.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        domain = InspectorConfiguration.DefaultsDomain(
            id: .init(rawValue: "test"),
            title: "Test",
            userDefaults: defaults,
            persistentDomainName: suiteName,
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
