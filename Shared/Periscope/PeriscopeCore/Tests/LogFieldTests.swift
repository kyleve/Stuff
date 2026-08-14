import Foundation
import PeriscopeCore
import Testing

private struct WrappedPayload: Codable, Equatable {
    @LogField("stable_key", exposure: .restricted, kind: .identifier)
    var renamedProperty: String

    init(renamedProperty: String) {
        _renamedProperty = LogField(
            wrappedValue: renamedProperty,
            "stable_key",
            exposure: .restricted,
            kind: .identifier,
        )
    }
}

struct LogFieldTests {
    @Test func wrapperEncodesOnlyItsRawValue() throws {
        let payload = WrappedPayload(renamedProperty: "sample-123")
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(object == ["renamedProperty": "sample-123"])
        #expect(try JSONDecoder().decode(WrappedPayload.self, from: data) == payload)
    }

    @Test func classifiedInputsRetainTheirRawValues() {
        let count: ClassifiedLogInput<LogFieldPolicy.Shared, LogFieldPolicy.Count, Int> =
            .shared(.count, 3)
        let identifier: ClassifiedLogInput<
            LogFieldPolicy.Restricted,
            LogFieldPolicy.Identifier,
            String
        > =
            .restricted(.identifier, "sample-123")

        #expect(count.value == 3)
        #expect(identifier.value == "sample-123")
    }
}
