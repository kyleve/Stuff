import Foundation
@_spi(Testing) import PeriscopeCore
import Testing

@LogScope("WrappedPayload")
private enum WrappedPayloadLog {
    @LogEvent("payload", message: "Wrapped payload")
    struct Payload: Equatable {
        @LogField("stable_key", exposure: .restricted, kind: .identifier)
        var renamedProperty: String
    }
}

private struct ClosedCategory: Codable, CaseIterable, RawRepresentable {
    static let allowed = Self(rawValue: "allowed")
    static let allCases = [allowed]

    let rawValue: String
}

struct LogFieldTests {
    @Test func wrapperEncodesOnlyItsRawValue() throws {
        let payload = WrappedPayloadLog.Payload(
            renamedProperty: .restricted(.identifier, "sample-123"),
        )
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(object == ["stable_key": "sample-123"])
        #expect(try JSONDecoder().decode(WrappedPayloadLog.Payload.self, from: data) == payload)
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

    @Test func closedCategoryValidationRejectsValuesOutsideAllCases() {
        #expect(isClosedLogCategory(ClosedCategory.allowed))
        #expect(isClosedLogCategory(ClosedCategory(rawValue: "injected")) == false)
    }

    @Test func sharedCategoryFactoriesAcceptMembersOfAllCases() {
        let required: ClassifiedLogInput<
            LogFieldPolicy.Shared,
            LogFieldPolicy.Category,
            ClosedCategory
        > = .shared(.category, .allowed)
        let optional: ClassifiedLogInput<
            LogFieldPolicy.Shared,
            LogFieldPolicy.Category,
            ClosedCategory?
        > = .shared(.category, .allowed)

        #expect(required.value.rawValue == "allowed")
        #expect(optional.value?.rawValue == "allowed")
    }
}
