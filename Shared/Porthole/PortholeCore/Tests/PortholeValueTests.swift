import Foundation
import PortholeCore
import Testing

struct PortholeValueTests {
    @Test func preservesNestedCodableUnsignedFieldsAndSignedBoundaries() throws {
        struct State: Codable, Equatable {
            let maximum: UInt64
            let minimum: Int64
            let nested: [String: [UInt64]]
            let fraction: Double
        }
        let state = State(
            maximum: .max,
            minimum: .min,
            nested: ["values": [.max, 9_007_199_254_740_993]],
            fraction: 1.25,
        )
        let encoded = try PortholeValue.encoding(state)
        #expect(encoded["maximum"] == .unsignedInteger(.max))
        #expect(encoded["minimum"] == .integer(.min))
        #expect(try encoded.decode(State.self) == state)
        #expect(try JSONDecoder().decode(PortholeValue.self, from: encoded.data()) == encoded)
    }

    @Test(arguments: ["18446744073709551616", "-9223372036854775809", "1e100", "-1e100"])
    func rejectsAmbiguousOutOfRangeIntegralTokens(token: String) {
        #expect(throws: (any Error).self) {
            try PortholeValue.parse(Data("{\"nested\": [\(token)]}".utf8))
        }
    }

    @Test func rejectsUnroundtrippableFloatingValuesBeforeEncoding() {
        #expect(throws: (any Error).self) { try PortholeValue.number(1e100).data() }
        #expect(throws: (any Error).self) { try PortholeValue.number(-1e100).data() }
    }

    @Test func comparesOnlyMathematicallyExactNumericRepresentations() throws {
        let largestWholeDouble = Double(UInt64.max).nextDown
        let exactInteger = try #require(UInt64(exactly: largestWholeDouble))
        let whole = PortholeValue.number(largestWholeDouble)
        #expect(try whole.json() == String(exactInteger))
        #expect(try PortholeValue.parse(whole.data()) == whole)
        let value = PortholeValue.object(["numbers": .array([
            .number(1),
            .unsignedInteger(1),
            .integer(-1),
            .number(1.25),
        ])])
        #expect(try PortholeValue.parse(value.data()) == value)
        #expect(PortholeValue
            .unsignedInteger(9_007_199_254_740_993) != .number(9_007_199_254_740_992))
        #expect(PortholeValue.integer(9_007_199_254_740_993) != .number(9_007_199_254_740_992))
        #expect(PortholeValue.unsignedInteger(.max) != .number(Double(UInt64.max)))
        #expect(PortholeValue.integer(.min) == .number(Double(Int64.min)))
        #expect(PortholeValue.integer(-1) != .unsignedInteger(.max))
    }

    @Test func preservesJSONTypesAndIntegerPrecision() throws {
        let value: PortholeValue = .object([
            "boolean": .bool(true),
            "integer": .integer(9_007_199_254_740_993),
            "fraction": .number(1.25),
            "nothing": .null,
            "array": .array([.string("hello"), .integer(-2)]),
        ])
        #expect(try PortholeValue.parse(value.data()) == value)
    }

    @Test func rejectsNonFiniteNumbers() {
        #expect(throws: (any Error).self) { try PortholeValue.number(.infinity).data() }
    }

    @Test func rejectsMalformedNestedValues() {
        #expect(throws: (any Error).self) {
            try PortholeValue.parse(Data("{\"value\": [1, invalid]}".utf8))
        }
    }
}
