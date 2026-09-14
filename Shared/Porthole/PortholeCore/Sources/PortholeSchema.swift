import Foundation

/// Describes and validates values before any native capability executes.
public indirect enum PortholeSchema: Sendable, Equatable, Codable {
    case any
    case boolean
    case integer
    case number
    case string
    case array(PortholeSchema)
    case object([PortholeParameter])
    case optional(PortholeSchema)

    public func validate(_ value: PortholeValue) throws {
        switch (self, value) {
            case (.any, _), (.boolean, .bool), (.integer, .integer), (.integer, .unsignedInteger),
                 (.number, .integer), (.number, .unsignedInteger), (.number, .number), (
                     .string,
                     .string
                 ),
                 (.optional, .null): return
            case let (.optional(schema), value): try schema.validate(value)
            case let (.array(schema), .array(values)):
                for value in values {
                    try schema.validate(value)
                }
            case let (.object(parameters), .object(values)):
                let known = Set(parameters.map(\.name))
                guard Set(values.keys).isSubset(of: known) else {
                    throw PortholeError.invalidArguments("Unknown argument names")
                }
                for parameter in parameters {
                    if let value = values[parameter.name] {
                        try parameter.schema.validate(value)
                    } else if parameter.required {
                        throw PortholeError.invalidArguments("Missing argument: \(parameter.name)")
                    }
                }
            case (.boolean, _), (.integer, _), (.number, _), (.string, _),
                 (.array, _), (.object, _):
                throw PortholeError.invalidArguments("Value does not match the parameter schema")
        }
    }

    public var jsonSchema: PortholeValue {
        switch self {
            case .any: .object([:])
            case .boolean: .object(["type": .string("boolean")])
            case .integer: .object(["type": .string("integer")])
            case .number: .object(["type": .string("number")])
            case .string: .object(["type": .string("string")])
            case let .array(element): .object([
                    "type": .string("array"),
                    "items": element.jsonSchema,
                ])
            case let .optional(wrapped):
                .object(["anyOf": .array([wrapped.jsonSchema, .object(["type": .string("null")])])])
            case let .object(parameters):
                .object([
                    "type": .string("object"),
                    "properties": .object(Dictionary(uniqueKeysWithValues: parameters.map {
                        ($0.name, $0.schema.jsonSchema)
                    })),
                    "required": .array(parameters.filter(\.required).map { .string($0.name) }),
                    "additionalProperties": .bool(false),
                ])
        }
    }
}

public struct PortholeParameter: Sendable, Equatable, Codable {
    public let name: String
    public let summary: String
    public let schema: PortholeSchema
    public let required: Bool

    public init(name: String, summary: String, schema: PortholeSchema, required: Bool) {
        self.name = name
        self.summary = summary
        self.schema = schema
        self.required = required
    }
}
