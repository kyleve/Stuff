import Foundation
@testable import PortholeCore
import Testing

struct PortholeSchemaTests {
    @Test func objectSchemaRendersJSONSchema() {
        let schema = PortholeSchema.object(
            ["year": .integer("Gregorian year")],
            required: ["year"],
            summary: "A year report request",
        )
        let json = schema.jsonSchema()
        #expect(json["type"]?.stringValue == "object")
        #expect(json["description"]?.stringValue == "A year report request")
        #expect(json["required"] == .array(["year"]))
        #expect(json["properties"]?["year"]?["type"]?.stringValue == "integer")
        #expect(json["properties"]?["year"]?["description"]?.stringValue == "Gregorian year")
    }

    @Test func dataAndDateRenderStringEncodings() {
        #expect(PortholeSchema.data().jsonSchema()["type"]?.stringValue == "string")
        #expect(PortholeSchema.data().jsonSchema()["contentEncoding"]?.stringValue == "base64")
        #expect(PortholeSchema.date().jsonSchema()["type"]?.stringValue == "string")
        #expect(PortholeSchema.date().jsonSchema()["format"]?.stringValue == "date-time")
    }

    @Test func stringEnumRendersAllowedValues() {
        let schema = PortholeSchema.string("level", allowedValues: ["info", "warning"])
        #expect(schema.jsonSchema()["enum"] == .array(["info", "warning"]))
    }

    @Test func arraySchemaRoundTripsWithRecursiveItems() throws {
        let schema = PortholeSchema.array(of: .object(["id": .string()], required: ["id"]))
        let restored = try jsonRoundTrip(schema)
        #expect(restored == schema)
        #expect(restored.items?.kind == .object)
        #expect(restored.jsonSchema()["items"]?["type"]?.stringValue == "object")
    }

    @Test func validateAcceptsWellFormedObject() throws {
        let schema = PortholeSchema.object(
            ["year": .integer(), "note": .string()],
            required: ["year"],
        )
        try schema.validate(["year": 2026, "note": "hi"])
        // Missing optional member is fine; unknown members are ignored.
        try schema.validate(["year": 2026, "extra": true])
    }

    @Test func validateRejectsMissingRequiredMember() {
        let schema = PortholeSchema.object(["year": .integer()], required: ["year"])
        #expect(throws: PortholeError.self) {
            try schema.validate(["note": "hi"])
        }
    }

    @Test func validateRejectsWrongScalarType() {
        let schema = PortholeSchema.object(["year": .integer()], required: ["year"])
        #expect(throws: PortholeError.self) {
            try schema.validate(["year": "not a number"])
        }
    }

    @Test func validateEnforcesAllowedValues() throws {
        let schema = PortholeSchema.object(
            ["level": .string(allowedValues: ["info", "warning"])],
            required: ["level"],
        )
        try schema.validate(["level": "warning"])
        #expect(throws: PortholeError.self) { try schema.validate(["level": "verbose"]) }
    }

    @Test func validateRecursesIntoArrayElements() throws {
        let schema = PortholeSchema.object(
            ["ids": .array(of: .integer())],
            required: ["ids"],
        )
        try schema.validate(["ids": .array([1, 2, 3])])
        #expect(throws: PortholeError.self) { try schema.validate(["ids": .array([1, "two"])]) }
    }

    @Test func validateAcceptsWholeNumberedDoubleAsInteger() throws {
        let schema = PortholeSchema.object(["n": .integer()], required: ["n"])
        try schema.validate(["n": .double(5.0)])
    }
}
