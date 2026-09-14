import PortholeCore
import Testing

struct PortholeSchemaTests {
    @Test func validatesBeforeDispatchAndRejectsExtraArguments() throws {
        let schema = PortholeSchema.object([
            PortholeParameter(name: "count", summary: "", schema: .integer, required: true),
            PortholeParameter(
                name: "filter",
                summary: "",
                schema: .optional(.string),
                required: false,
            ),
        ])
        try schema.validate(.object(["count": .integer(3)]))
        try schema.validate(.object(["count": .unsignedInteger(.max)]))
        #expect(throws: PortholeError.self) { try schema.validate(.object([:])) }
        #expect(throws: PortholeError.self) {
            try schema.validate(.object(["count": .string("3")]))
        }
        #expect(throws: PortholeError.self) {
            try schema.validate(.object(["count": .integer(3), "typo": .bool(true)]))
        }
    }
}
