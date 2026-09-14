import Foundation

/// Tool values preserve integer precision and reject non-finite JSON numbers.
public indirect enum PortholeValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case string(String)
    case array([PortholeValue])
    case object([String: PortholeValue])

    /// JSON does not preserve the signed or floating representation of an exact integer.
    /// Operation identities compare their mathematical values without rounding either side.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
            case (.null, .null): true
            case let (.bool(lhs), .bool(rhs)): lhs == rhs
            case let (.string(lhs), .string(rhs)): lhs == rhs
            case let (.integer(lhs), .integer(rhs)): lhs == rhs
            case let (.unsignedInteger(lhs), .unsignedInteger(rhs)): lhs == rhs
            case let (.number(lhs), .number(rhs)): lhs == rhs
            case let (.integer(signed), .unsignedInteger(unsigned)),
                 let (.unsignedInteger(unsigned), .integer(signed)): UInt64(exactly: signed) ==
            unsigned
            case let (.integer(integer), .number(number)),
                 let (.number(number), .integer(integer)): Int64(exactly: number) == integer
            case let (.unsignedInteger(integer), .number(number)),
                 let (.number(number), .unsignedInteger(integer)): UInt64(exactly: number) ==
            integer
            case let (.array(lhs), .array(rhs)): lhs == rhs
            case let (.object(lhs), .object(rhs)): lhs == rhs
            case (.null, _), (.bool, _), (.string, _), (.integer, _),
                 (.unsignedInteger, _), (.number, _), (.array, _), (.object, _): false
        }
    }

    /// A tool value is raw JSON, not Swift's associated-value enum wire shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try Self.alternative(Bool.self, in: container) { self = .bool(value) }
        else if let value = try Self.numeric(in: container) { self = value }
        else if let value = try Self
            .alternative(String.self, in: container) { self = .string(value) }
        else if let value = try Self
            .alternative([PortholeValue].self, in: container) { self = .array(value) }
        else { self = try .object(container.decode([String: PortholeValue].self)) }
    }

    private static func numeric(in container: any SingleValueDecodingContainer) throws -> Self? {
        guard let floating = try alternative(Double.self, in: container) else { return nil }
        guard floating.isFinite else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Porthole numbers must be finite",
            )
        }
        do { return try .integer(container.decode(Int64.self)) }
        catch {
            // Foundation can throw its private JSONError for fractional values.
            // Probe the unsigned integer directly before accepting a floating value.
            do { return try .unsignedInteger(container.decode(UInt64.self)) }
            catch {
                guard floating.rounded(.towardZero) != floating else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Porthole integer values must fit Int64 or UInt64; refusing a rounded Double fallback",
                    )
                }
                return .number(floating)
            }
        }
    }

    private static func alternative<Value: Decodable>(
        _ type: Value.Type,
        in container: any SingleValueDecodingContainer,
    ) throws -> Value? {
        do { return try container.decode(type) }
        catch DecodingError.typeMismatch { return nil }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .null: try container.encodeNil()
            case let .bool(value): try container.encode(value)
            case let .integer(value): try container.encode(value)
            case let .unsignedInteger(value): try container.encode(value)
            case let .number(value):
                if let integer = Int64(exactly: value) { try container.encode(integer) }
                else if let integer = UInt64(exactly: value) { try container.encode(integer) }
                else if value.isFinite,
                        value.rounded(.towardZero) != value { try container.encode(value) }
                else {
                    throw EncodingError.invalidValue(
                        value,
                        .init(
                            codingPath: encoder.codingPath,
                            debugDescription: "Porthole numbers must be finite; integral values must fit Int64 or UInt64",
                        ),
                    )
                }
            case let .string(value): try container.encode(value)
            case let .array(value): try container.encode(value)
            case let .object(value): try container.encode(value)
        }
    }

    public subscript(key: String) -> PortholeValue? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func json() throws -> String {
        try String(decoding: data(), as: UTF8.self)
    }

    public static func parse(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    public static func encoding(_ value: some Encodable) throws -> Self {
        try parse(JSONEncoder().encode(value))
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: data())
    }
}
