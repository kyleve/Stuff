import PeriscopeCore

enum ProjectionTestValues {
    static let error = LogLevel(name: "Custom failure", severity: 99)
    enum Category: String, Codable, CaseIterable { case ready }

    struct OpenCategory: Codable, RawRepresentable, CaseIterable {
        var rawValue: String
        static let allCases = [Self(rawValue: "ready")]
    }

    struct ObjectCategory: Codable, RawRepresentable, CaseIterable {
        var rawValue: String
        static let allCases = [Self(rawValue: "ready")]

        /// Deliberately incompatible wire shape exercises fail-closed category export.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(["rawValue": rawValue, "email": "private@example.test"])
        }
    }
}

@LogScope("Projection")
enum ProjectionTestLog {
    @LogEvent("aliases", level: ProjectionTestValues.error, message: "Aliases")
    struct Aliases {
        typealias Count = Swift.Int
        // swiftformat:disable:next typeSugar
        typealias OptionalCategory = Optional<ProjectionTestValues.Category>
        @PeriscopeCore.LogField(exposure: .shareable, kind: .count) var count: Count
        @PeriscopeCore.LogField(
            exposure: .shareable,
            kind: .category,
        ) var category: OptionalCategory
        @PeriscopeCore.LogField(exposure: .shareable, kind: .json) var json: PeriscopeCore
            .JSONValue?
        @PeriscopeCore.LogField(exposure: .shareable, kind: .boolean) var boolean: Swift.Bool
    }

    @LogEvent("shadow", message: "Shadow")
    struct LogField {
        @PeriscopeCore.LogField(exposure: .restricted, kind: .identifier) var value: String
    }

    @LogEvent("open", message: "Open")
    struct Open {
        @PeriscopeCore
            .LogField(exposure: .shareable, kind: .category) var category: ProjectionTestValues
            .OpenCategory
    }

    @LogEvent("object", message: "Object")
    struct Object {
        @PeriscopeCore
            .LogField(exposure: .shareable, kind: .category) var category: ProjectionTestValues
            .ObjectCategory
    }
}
