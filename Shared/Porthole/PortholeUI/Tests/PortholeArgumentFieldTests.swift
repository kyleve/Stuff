import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeArgumentFieldTests {
    @Test func typedFieldsPreserveWireTypes() throws {
        let field = PortholeArgumentField(parameter: .init(
            name: "count",
            summary: "Count",
            schema: .integer,
            required: true,
        ))
        field.integerText = "9"
        #expect(try field.value() == .integer(9))
        let boolean = PortholeArgumentField(parameter: .init(
            name: "enabled",
            summary: "Enabled",
            schema: .boolean,
            required: true,
        ))
        boolean.boolean = true
        #expect(try boolean.value() == .bool(true))
    }

    @Test func integerTextPreservesBothFullWidthRangesAndRejectsOverflow() throws {
        let field = PortholeArgumentField(parameter: .init(
            name: "count",
            summary: "Count",
            schema: .integer,
            required: true,
        ))
        field.integerText = String(UInt64.max)
        #expect(try field.value() == .unsignedInteger(UInt64.max))
        field.integerText = String(Int64.min)
        #expect(try field.value() == .integer(Int64.min))
        for invalid in ["18446744073709551616", "-9223372036854775809", "1.5", "invalid"] {
            field.integerText = invalid
            #expect(throws: PortholeError.self) { try field.value() }
        }
    }

    @Test func complexFieldsRejectInvalidJSONAndSchemaMismatches() throws {
        let field = PortholeArgumentField(parameter: .init(
            name: "items",
            summary: "Items",
            schema: .array(.integer),
            required: true,
        ))
        field.text = "[1,2]"
        #expect(try field.value() == .array([.integer(1), .integer(2)]))
        field.text = "[\"wrong\"]"
        #expect(throws: PortholeError.self) { try field.value() }
        field.text = "not JSON"
        #expect(throws: (any Error).self) { try field.value() }
    }
}
