import Foundation

/// Whether a classified field can enter baseline remote diagnostics.
public enum LogFieldExposure: Equatable, Sendable {
    case shareable
    case restricted
}

/// The semantic role of a classified event field.
public enum LogFieldKind: Equatable, Sendable {
    case boolean
    case count
    case limit
    case duration
    case category
    case json
    case pii
    case identifier
    case location
    case userContent
    case errorDetails
    case dateTime
    case pathOrURL
    case arbitraryText
    case domainValue
    case technicalState
}

/// The shareable subset of ``LogFieldKind``.
public enum ShareableLogFieldKind: Equatable, Sendable {
    case boolean
    case count
    case limit
    case duration
    case category
    case json
}

/// A stable event-field key supplied as a source literal.
public struct LogFieldKey: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: StaticString) {
        self.rawValue = String(describing: rawValue)
    }
}

/// A provider-neutral representation of a baseline-shareable value.
public enum ShareableLogFieldValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case json(JSONValue)
}

/// The safe field projection consumed by baseline remote sinks.
public enum ClassifiedLogField: Equatable, Sendable {
    case shareable(
        key: LogFieldKey,
        kind: ShareableLogFieldKind,
        value: ShareableLogFieldValue,
    )
    case restricted(key: LogFieldKey, kind: LogFieldKind)
}

/// Phantom types used by ``ClassifiedLogInput``.
public enum LogFieldPolicy {
    public enum Shared {}
    public enum Restricted {}
    public enum Boolean {}
    public enum Count {}
    public enum Limit {}
    public enum Duration {}
    public enum Category {}
    public enum JSON {}
    public enum PII {}
    public enum Identifier {}
    public enum Location {}
    public enum UserContent {}
    public enum ErrorDetails {}
    public enum DateTime {}
    public enum PathOrURL {}
    public enum ArbitraryText {}
    public enum DomainValue {}
    public enum TechnicalState {}
}

/// A compiler-checked token for one semantic field kind.
public struct LogFieldKindToken<Kind>: Sendable {
    fileprivate init() {}
}

extension LogFieldKindToken {
    public static var boolean: LogFieldKindToken<LogFieldPolicy.Boolean> {
        .init()
    }

    public static var count: LogFieldKindToken<LogFieldPolicy.Count> {
        .init()
    }

    public static var limit: LogFieldKindToken<LogFieldPolicy.Limit> {
        .init()
    }

    public static var duration: LogFieldKindToken<LogFieldPolicy.Duration> {
        .init()
    }

    public static var category: LogFieldKindToken<LogFieldPolicy.Category> {
        .init()
    }

    public static var json: LogFieldKindToken<LogFieldPolicy.JSON> {
        .init()
    }

    public static var pii: LogFieldKindToken<LogFieldPolicy.PII> {
        .init()
    }

    public static var identifier: LogFieldKindToken<LogFieldPolicy.Identifier> {
        .init()
    }

    public static var location: LogFieldKindToken<LogFieldPolicy.Location> {
        .init()
    }

    public static var userContent: LogFieldKindToken<LogFieldPolicy.UserContent> {
        .init()
    }

    public static var errorDetails: LogFieldKindToken<LogFieldPolicy.ErrorDetails> {
        .init()
    }

    public static var dateTime: LogFieldKindToken<LogFieldPolicy.DateTime> {
        .init()
    }

    public static var pathOrURL: LogFieldKindToken<LogFieldPolicy.PathOrURL> {
        .init()
    }

    public static var arbitraryText: LogFieldKindToken<LogFieldPolicy.ArbitraryText> {
        .init()
    }

    public static var domainValue: LogFieldKindToken<LogFieldPolicy.DomainValue> {
        .init()
    }

    public static var technicalState: LogFieldKindToken<LogFieldPolicy.TechnicalState> {
        .init()
    }
}

/// A field value whose exposure, semantic kind, and Swift type are checked by the compiler.
public struct ClassifiedLogInput<Exposure, Kind, Value: Codable & Sendable>: Sendable {
    public let value: Value

    private init(value: Value) {
        self.value = value
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Boolean, Value == Bool
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Bool,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Boolean, Value == Bool?
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Bool?,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Count, Value == Int
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Int,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Count, Value == Int?
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Int?,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Limit, Value == Int
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Int,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Limit, Value == Int?
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Int?,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Duration, Value == Duration
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Duration,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Duration, Value == Duration?
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Duration?,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Category,
    Value: Codable & Sendable & CaseIterable & RawRepresentable,
    Value.RawValue == String
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: Value,
    ) -> Self {
        preconditionClosedCategory(value)
        return .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.Category
{
    public static func shared<Category>(
        _: LogFieldKindToken<Kind>,
        _ value: Category?,
    ) -> Self where
        Value == Category?,
        Category: Codable & Sendable & CaseIterable & RawRepresentable,
        Category.RawValue == String
    {
        if let value {
            preconditionClosedCategory(value)
        }
        return .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.JSON, Value == JSONValue
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: JSONValue,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Shared,
    Kind == LogFieldPolicy.JSON, Value == JSONValue?
{
    public static func shared(
        _: LogFieldKindToken<Kind>,
        _ value: JSONValue?,
    ) -> Self {
        .init(value: value)
    }
}

extension ClassifiedLogInput where Exposure == LogFieldPolicy.Restricted {
    public static func restricted(
        _: LogFieldKindToken<Kind>,
        _ value: Value,
    ) -> Self {
        .init(value: value)
    }
}

extension Duration {
    /// The provider-neutral millisecond representation used by classified fields.
    public var periscopeMilliseconds: Double {
        let components = components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

@_spi(Testing)
public func isClosedLogCategory<Value: CaseIterable & RawRepresentable>(_ value: Value) -> Bool
    where Value.RawValue == String
{
    Value.allCases.contains { $0.rawValue == value.rawValue }
}

private func preconditionClosedCategory<Value: CaseIterable & RawRepresentable>(_ value: Value)
    where Value.RawValue == String
{
    precondition(
        isClosedLogCategory(value),
        "Shareable log categories must be members of a closed CaseIterable set",
    )
}
