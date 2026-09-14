import Foundation
import Observation
import PortholeCore

/// A form input keeps one representation that matches its parameter schema.
@MainActor @Observable
final class PortholeArgumentField: Identifiable {
    enum Input {
        case boolean(Bool), integer(String), number(Double), string(String), json(String)
    }

    let parameter: PortholeParameter
    var input: Input
    nonisolated var id: String {
        parameter.name
    }

    init(parameter: PortholeParameter) {
        self.parameter = parameter
        switch parameter.schema {
            case .boolean: input = .boolean(false)
            case .integer: input = .integer("0")
            case .number: input = .number(0)
            case .string: input = .string("")
            case .array: input = .json("[]")
            case .object: input = .json("{}")
            case .any, .optional: input = .json("null")
        }
    }

    var boolean: Bool {
        get {
            guard case let .boolean(value) = input
            else { preconditionFailure("Expected a boolean field") }; return value
        }
        set { input = .boolean(newValue) }
    }

    var integerText: String {
        get {
            guard case let .integer(value) = input
            else { preconditionFailure("Expected an integer field") }; return value
        }
        set { input = .integer(newValue) }
    }

    var number: Double {
        get {
            guard case let .number(value) = input
            else { preconditionFailure("Expected a numeric field") }; return value
        }
        set { input = .number(newValue) }
    }

    var text: String {
        get {
            switch input {
                case let .string(value), let .json(value): value
                case .boolean, .integer, .number: preconditionFailure("Expected a text field")
            }
        }
        set {
            switch input {
                case .string: input = .string(newValue)
                case .json: input = .json(newValue)
                case .boolean, .integer, .number: preconditionFailure("Expected a text field")
            }
        }
    }

    func value() throws -> PortholeValue {
        let value: PortholeValue = switch input {
            case let .boolean(input): .bool(input)
            case let .integer(input): try integerValue(input)
            case let .number(input): .number(input)
            case let .string(input): .string(input)
            case let .json(input): try JSONDecoder().decode(
                    PortholeValue.self,
                    from: Data(input.utf8),
                )
        }
        try parameter.schema.validate(value)
        return value
    }

    private func integerValue(_ text: String) throws -> PortholeValue {
        if let signed = Int64(text) { return .integer(signed) }
        if let unsigned = UInt64(text) { return .unsignedInteger(unsigned) }
        throw PortholeError
            .invalidArguments(
                "\(parameter.name) requires a decimal integer from \(Int64.min) through \(UInt64.max).",
            )
    }
}
