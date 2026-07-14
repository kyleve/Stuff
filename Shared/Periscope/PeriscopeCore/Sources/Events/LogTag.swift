import Foundation

/// A typed tag key — apps declare their keys once so a tag can't silently
/// typo into a new, untracked identifier:
///
/// ```swift
/// extension LogTagKey {
///     static let paymentID = LogTagKey("payment-id")
/// }
/// ```
public struct LogTagKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

/// A tag's value: the common primitives as typed cases, or any `Codable`
/// value via ``encoding(_:)``. Literals convert directly, so
/// `log.tagged(.retryCount, 3)` and `log.tagged(.paymentID, "pay_1")` read
/// naturally.
public enum LogTagValue: Hashable, Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    /// Any other `Codable` value, carried as canonical JSON — see
    /// ``encoding(_:)``.
    case encoded(json: String)

    /// Wrap an arbitrary `Codable` value as canonical (key-sorted) JSON,
    /// so equal values always compare and persist identically.
    public static func encoding(_ value: some Encodable & Sendable) throws -> LogTagValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try .encoded(json: String(decoding: encoder.encode(value), as: UTF8.self))
    }

    /// The canonical display/persistence string for this value.
    public var stringValue: String {
        switch self {
            case let .string(value): value
            case let .int(value): String(value)
            case let .double(value): String(value)
            case let .bool(value): String(value)
            case let .encoded(json): json
        }
    }

    /// The persistence discriminator, so `.int(3)` and `.string("3")`
    /// round-trip as themselves.
    var kind: String {
        switch self {
            case .string: "string"
            case .int: "int"
            case .double: "double"
            case .bool: "bool"
            case .encoded: "encoded"
        }
    }

    /// Restore from persisted columns. An unrecognized kind (a future
    /// case read by an old build) degrades to `.string` — the value stays
    /// visible rather than dropping the tag.
    init(kind: String, stored: String) {
        switch kind {
            case "int": self = Int(stored).map(LogTagValue.int) ?? .string(stored)
            case "double": self = Double(stored).map(LogTagValue.double) ?? .string(stored)
            case "bool": self = Bool(stored).map(LogTagValue.bool) ?? .string(stored)
            case "encoded": self = .encoded(json: stored)
            default: self = .string(stored)
        }
    }
}

extension LogTagValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral
{
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

/// Types that convert directly into a tag value, so `tagged(_:_:)` accepts
/// plain `String`/`Int`/`Double`/`Bool` variables without wrapping.
public protocol LogTagValueConvertible {
    var logTagValue: LogTagValue { get }
}

extension LogTagValue: LogTagValueConvertible {
    public var logTagValue: LogTagValue {
        self
    }
}

extension String: LogTagValueConvertible {
    public var logTagValue: LogTagValue {
        .string(self)
    }
}

extension Int: LogTagValueConvertible {
    public var logTagValue: LogTagValue {
        .int(self)
    }
}

extension Double: LogTagValueConvertible {
    public var logTagValue: LogTagValue {
        .double(self)
    }
}

extension Bool: LogTagValueConvertible {
    public var logTagValue: LogTagValue {
        .bool(self)
    }
}

/// One key/value tag, as stamped, stored, and queried.
///
/// Tags are orthogonal to the scope hierarchy: a tagged context stamps every
/// event logged through it (e.g. the current payment's ID across a whole UI
/// flow), and any event can carry any tags regardless of where it sits in
/// the tree.
public struct LogTag: Hashable, Sendable, Codable {
    public let key: LogTagKey
    public let value: LogTagValue

    public init(key: LogTagKey, value: LogTagValue) {
        self.key = key
        self.value = value
    }

    /// Key, value kind, and canonical value joined into one string — the
    /// store's single indexed column, so tag predicates stay one
    /// comparison. The kind keeps `.int(3)` and `.string("3")` distinct.
    public var pair: String {
        "\(key.rawValue)\u{1F}\(value.kind)\u{1F}\(value.stringValue)"
    }
}

extension [LogTag] {
    /// The value for `key`, if present. Tag lists are unique by key.
    public subscript(key: LogTagKey) -> LogTagValue? {
        first { $0.key == key }?.value
    }

    /// Set `value` for `key` — replacing in place when the key is already
    /// present (a re-tag keeps its position), appending otherwise.
    mutating func set(_ value: LogTagValue, forKey key: LogTagKey) {
        if let index = firstIndex(where: { $0.key == key }) {
            self[index] = LogTag(key: key, value: value)
        } else {
            append(LogTag(key: key, value: value))
        }
    }

    /// This list plus `other`'s tags for keys not already present — the
    /// receiver wins key conflicts (link semantics: the left side is
    /// primary).
    func merging(_ other: [LogTag]) -> [LogTag] {
        var merged = self
        for tag in other where merged[tag.key] == nil {
            merged.append(tag)
        }
        return merged
    }
}
