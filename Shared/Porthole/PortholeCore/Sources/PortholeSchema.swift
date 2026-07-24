import Foundation

/// A small, self-describing shape for a connector's action parameters and a
/// data source's rows/filters. It exists so two things can be derived from one
/// source of truth: a JSON-Schema object (``jsonSchema()``) that feeds an MCP
/// tool's `inputSchema`, and a runtime ``validate(_:)`` the device applies to
/// incoming parameters before handing them to a connector handler.
///
/// It is deliberately a subset of JSON Schema — enough to describe the
/// descriptive payloads Porthole carries, not a general validator.
public struct PortholeSchema: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case object, array, string, integer, number, boolean, data, date
    }

    public var kind: Kind
    /// Rendered as JSON Schema `description`; write it for an LLM reader.
    public var summary: String?
    /// Member schemas when `kind == .object`.
    public var properties: [String: PortholeSchema]?
    /// Required member keys when `kind == .object`.
    public var required: [String]?
    /// Permitted string values (JSON Schema `enum`) when `kind == .string`.
    public var allowedValues: [String]?

    /// Element schema when `kind == .array`, boxed so this value type can
    /// describe itself recursively.
    public var items: PortholeSchema? {
        get { itemsBox?.schema }
        set { itemsBox = newValue.map(Box.init) }
    }

    private var itemsBox: Box?

    private enum CodingKeys: String, CodingKey {
        case kind, summary, properties, required, allowedValues
        case itemsBox = "items"
    }

    public init(
        kind: Kind,
        summary: String? = nil,
        properties: [String: PortholeSchema]? = nil,
        required: [String]? = nil,
        allowedValues: [String]? = nil,
        items: PortholeSchema? = nil,
    ) {
        self.kind = kind
        self.summary = summary
        self.properties = properties
        self.required = required
        self.allowedValues = allowedValues
        itemsBox = items.map(Box.init)
    }

    /// Boxes a child schema so `PortholeSchema` (a value type) can hold one
    /// recursively; encodes transparently as the wrapped schema.
    private final class Box: Sendable, Equatable, Codable {
        let schema: PortholeSchema
        init(_ schema: PortholeSchema) {
            self.schema = schema
        }

        static func == (lhs: Box, rhs: Box) -> Bool {
            lhs.schema == rhs.schema
        }

        init(from decoder: Decoder) throws {
            schema = try decoder.singleValueContainer().decode(PortholeSchema.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(schema)
        }
    }
}

// MARK: - Builders

extension PortholeSchema {
    public static func object(
        _ properties: [String: PortholeSchema],
        required: [String] = [],
        summary: String? = nil,
    ) -> PortholeSchema {
        PortholeSchema(kind: .object, summary: summary, properties: properties, required: required)
    }

    public static func array(of items: PortholeSchema, summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .array, summary: summary, items: items)
    }

    public static func string(
        _ summary: String? = nil,
        allowedValues: [String]? = nil,
    ) -> PortholeSchema {
        PortholeSchema(kind: .string, summary: summary, allowedValues: allowedValues)
    }

    public static func integer(_ summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .integer, summary: summary)
    }

    public static func number(_ summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .number, summary: summary)
    }

    public static func boolean(_ summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .boolean, summary: summary)
    }

    public static func data(_ summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .data, summary: summary)
    }

    public static func date(_ summary: String? = nil) -> PortholeSchema {
        PortholeSchema(kind: .date, summary: summary)
    }
}

// MARK: - JSON Schema rendering

extension PortholeSchema {
    /// Renders a JSON-Schema object as a `PortholeValue` — the shape an MCP
    /// tool's `inputSchema` expects.
    public func jsonSchema() -> PortholeValue {
        var object: [String: PortholeValue] = [:]
        if let summary { object["description"] = .string(summary) }

        switch kind {
            case .object:
                object["type"] = "object"
                if let properties {
                    object["properties"] = .object(properties.mapValues { $0.jsonSchema() })
                }
                if let required, !required.isEmpty {
                    object["required"] = .array(required.map(PortholeValue.string))
                }
            case .array:
                object["type"] = "array"
                if let items { object["items"] = items.jsonSchema() }
            case .string:
                object["type"] = "string"
                if let allowedValues {
                    object["enum"] = .array(allowedValues.map(PortholeValue.string))
                }
            case .integer:
                object["type"] = "integer"
            case .number:
                object["type"] = "number"
            case .boolean:
                object["type"] = "boolean"
            case .data:
                object["type"] = "string"
                object["contentEncoding"] = "base64"
            case .date:
                object["type"] = "string"
                object["format"] = "date-time"
        }
        return .object(object)
    }
}

// MARK: - Validation

extension PortholeSchema {
    /// Validates `value` against this schema, throwing
    /// ``PortholeError/invalidParameters(_:)`` with a human-readable path on the
    /// first mismatch. Known object members are type-checked; unknown members
    /// are ignored (forward-compatible), but every `required` member must be
    /// present. The device runtime calls this before invoking a handler.
    public func validate(_ value: PortholeValue) throws {
        try validate(value, path: "")
    }

    private func validate(_ value: PortholeValue, path: String) throws {
        func fail(_ reason: String) -> PortholeError {
            let location = path.isEmpty ? "value" : "`\(path)`"
            return PortholeError.invalidParameters("\(location) \(reason)")
        }

        switch kind {
            case .object:
                guard case let .object(members) = value else { throw fail("must be an object") }
                for key in required ?? [] where members[key] == nil {
                    throw fail("is missing required member `\(key)`")
                }
                for (key, subschema) in properties ?? [:] {
                    if let member = members[key] {
                        try subschema.validate(member, path: path.isEmpty ? key : "\(path).\(key)")
                    }
                }
            case .array:
                guard case let .array(elements) = value else { throw fail("must be an array") }
                if let items {
                    for (index, element) in elements.enumerated() {
                        try items.validate(element, path: "\(path)[\(index)]")
                    }
                }
            case .string:
                guard case let .string(string) = value else { throw fail("must be a string") }
                if let allowedValues, !allowedValues.contains(string) {
                    throw fail(
                        "must be one of \(allowedValues.map { "\"\($0)\"" }.joined(separator: ", "))",
                    )
                }
            case .integer:
                guard value.intValue != nil else { throw fail("must be an integer") }
            case .number:
                guard value.doubleValue != nil else { throw fail("must be a number") }
            case .boolean:
                guard value.boolValue != nil else { throw fail("must be a boolean") }
            case .data:
                guard value.dataValue != nil else { throw fail("must be binary data") }
            case .date:
                guard value.dateValue != nil else { throw fail("must be a date") }
        }
    }
}
