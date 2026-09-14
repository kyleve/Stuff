import AI
import PortholeCore

/// The SDK uses Double for JSON numbers. Reject lossy inputs and stringify large outputs.
enum PortholeAgentValue {
    private static let safeInteger: Int64 = 9_007_199_254_740_991

    static func input(_ value: JSONValue) throws -> PortholeValue {
        switch value {
            case .null: return .null
            case let .bool(value): return .bool(value)
            case let .string(value): return .string(value)
            case let .number(value):
                guard value.isFinite else { throw PortholeAgentError.invalidNumber }
                if value.rounded(.towardZero) == value {
                    guard abs(value) <= Double(safeInteger)
                    else { throw PortholeAgentError.unsafeInteger }
                    return .integer(Int64(value))
                }
                return .number(value)
            case let .array(values): return try .array(values.map(input))
            case let .object(values): return try .object(values.mapValues(input))
        }
    }

    static func output(_ value: PortholeValue) throws -> JSONValue {
        switch value {
            case .null: return .null
            case let .bool(value): return .bool(value)
            case let .string(value): return .string(value)
            case let .integer(value):
                if value < -safeInteger || value > safeInteger { return .string(String(value)) }
                return .number(Double(value))
            case let .unsignedInteger(value):
                if value > UInt64(safeInteger) { return .string(String(value)) }
                return .number(Double(value))
            case let .number(value):
                guard value.isFinite else { throw PortholeAgentError.invalidNumber }
                return .number(value)
            case let .array(values): return try .array(values.map(output))
            case let .object(values): return try .object(values.mapValues(output))
        }
    }
}
