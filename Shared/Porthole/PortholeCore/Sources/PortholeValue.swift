import Foundation

/// The single data currency that crosses the Porthole wire: every action
/// parameter and result, every data-source row, and every stream event is a
/// `PortholeValue`.
///
/// It is a small, self-describing JSON-shaped tree with two extensions over
/// plain JSON — `.data` and `.date` — so binary blobs and timestamps survive a
/// round-trip unambiguously instead of decaying into strings the far side has
/// to guess about.
///
/// ## Wire shape
///
/// Scalars encode as the bare JSON scalar (`true`, `42`, `1.5`, `"hi"`, `null`).
/// `.data` and `.date` encode as tagged single-key objects — `{"$data":
/// "<base64>"}` and `{"$date": "<ISO8601>"}` — which is what lets the decoder
/// tell them apart from an ordinary `.object`. A genuine object whose *only*
/// key is `$data`/`$date` would be read back as the tagged form; that ambiguity
/// is deliberate and harmless for the descriptive payloads Porthole carries.
public enum PortholeValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([PortholeValue])
    case object([String: PortholeValue])
}

// MARK: - Convenience accessors

extension PortholeValue {
    public var isNull: Bool {
        self == .null
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    /// The integer value, widening `.int` and accepting a whole-numbered
    /// `.double` (JSON has one number type, so an integer can arrive as either).
    public var intValue: Int64? {
        switch self {
            case let .int(value): value
            case let .double(value) where value.rounded() == value: Int64(value)
            default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
            case let .double(value): value
            case let .int(value): Double(value)
            default: nil
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var dataValue: Data? {
        if case let .data(value) = self { return value }
        return nil
    }

    public var dateValue: Date? {
        if case let .date(value) = self { return value }
        return nil
    }

    public var arrayValue: [PortholeValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: PortholeValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    /// Reads a member of an `.object`; `nil` for any other case or a missing key.
    public subscript(key: String) -> PortholeValue? {
        objectValue?[key]
    }

    /// Reads an element of an `.array`; `nil` for any other case or out-of-range.
    public subscript(index: Int) -> PortholeValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

// MARK: - Literal conformances (test & call-site ergonomics)

extension PortholeValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension PortholeValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension PortholeValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .int(value)
    }
}

extension PortholeValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension PortholeValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension PortholeValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PortholeValue...) {
        self = .array(elements)
    }
}

extension PortholeValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, PortholeValue)...) {
        self = .object(Dictionary(elements) { first, _ in first })
    }
}

// MARK: - Codable

extension PortholeValue: Codable {
    /// Dynamic key so an `.object` (and the `$data`/`$date` tags) can use a
    /// keyed container without a fixed `CodingKeys` set. Named to avoid shadowing
    /// the `ExpressibleByDictionaryLiteral.Key` associated type.
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }

        static let data = DynamicCodingKey("$data")
        static let date = DynamicCodingKey("$date")
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
            case .null:
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            case let .bool(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .int(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .double(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .string(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .data(value):
                var container = encoder.container(keyedBy: DynamicCodingKey.self)
                try container.encode(value.base64EncodedString(), forKey: .data)
            case let .date(value):
                var container = encoder.container(keyedBy: DynamicCodingKey.self)
                try container.encode(PortholeISO8601.string(from: value), forKey: .date)
            case let .array(value):
                var container = encoder.unkeyedContainer()
                for element in value {
                    try container.encode(element)
                }
            case let .object(value):
                var container = encoder.container(keyedBy: DynamicCodingKey.self)
                for (key, element) in value {
                    try container.encode(element, forKey: DynamicCodingKey(key))
                }
        }
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), single.decodeNil() {
            self = .null
            return
        }
        if let single = try? decoder.singleValueContainer() {
            if let value = try? single.decode(Bool.self) { self = .bool(value); return }
            if let value = try? single.decode(Int64.self) { self = .int(value); return }
            if let value = try? single.decode(Double.self) { self = .double(value); return }
            if let value = try? single.decode(String.self) { self = .string(value); return }
        }
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            let keys = keyed.allKeys.map(\.stringValue)
            if keys == ["$data"], let base64 = try? keyed.decode(String.self, forKey: .data),
               let data = Data(base64Encoded: base64)
            {
                self = .data(data)
                return
            }
            if keys == ["$date"], let iso = try? keyed.decode(String.self, forKey: .date),
               let date = PortholeISO8601.date(from: iso)
            {
                self = .date(date)
                return
            }
            var object: [String: PortholeValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(PortholeValue.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [PortholeValue] = []
            if let count = unkeyed.count { array.reserveCapacity(count) }
            while !unkeyed.isAtEnd {
                try array.append(unkeyed.decode(PortholeValue.self))
            }
            self = .array(array)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized PortholeValue shape",
            ),
        )
    }
}

/// Shared ISO 8601 formatting for `.date` wire values (millisecond precision).
enum PortholeISO8601 {
    /// `ISO8601DateFormatter` is immutable after configuration and thread-safe
    /// for concurrent formatting/parsing, so a shared instance is safe here.
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
