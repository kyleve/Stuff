import Foundation
import PeriscopeCore
import Testing

struct JSONValueTests {
    @Test(arguments: [
        JSONValue.null,
        .bool(true),
        .int(42),
        .double(4.25),
        .string("value"),
        .array([]),
        .object([:]),
        .array([.null, .object(["nested": .array([.int(1), .bool(false)])])]),
    ])
    func roundTripsNaturalJSON(_ value: JSONValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test func preservesIntegerAndDoubleCases() throws {
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data("1".utf8)) == .int(1))
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data("1.5".utf8)) == .double(1.5))
    }

    @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
    func rejectsNonfiniteDoubles(_ value: Double) {
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(JSONValue.double(value))
        }
    }

    @Test func convertsArbitraryEncodableValues() throws {
        struct Value: Encodable, Sendable {
            let count: Int
            let complete: Bool
        }

        #expect(try JSONValue.encoding(Value(count: 3, complete: true)) == .object([
            "complete": .bool(true),
            "count": .int(3),
        ]))
    }

    @Test func propagatesArbitraryEncodableFailure() {
        struct Failing: Encodable, Sendable {
            func encode(to _: any Encoder) throws {
                throw Failure.expected
            }
        }
        enum Failure: Error {
            case expected
        }

        #expect(throws: Failure.expected) {
            try JSONValue.encoding(Failing())
        }
    }
}
