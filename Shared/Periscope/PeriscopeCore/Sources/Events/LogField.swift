import Foundation

/// Stores one event payload value without persisting its classification metadata.
@propertyWrapper
public struct LogField<Value: Codable & Sendable>: Codable, Sendable {
    private var storage: Value?
    private var isInitialized: Bool

    public var wrappedValue: Value {
        get {
            precondition(isInitialized, "A LogField must be initialized before use")
            return storage!
        }
        set {
            storage = newValue
            isInitialized = true
        }
    }

    public init(
        _: StaticString,
        exposure _: LogFieldExposure,
        kind _: LogFieldKind,
    ) {
        storage = nil
        isInitialized = false
    }

    public init(
        wrappedValue: Value,
        _: StaticString,
        exposure _: LogFieldExposure,
        kind _: LogFieldKind,
    ) {
        storage = wrappedValue
        isInitialized = true
    }

    public init(from decoder: any Decoder) throws {
        storage = try decoder.singleValueContainer().decode(Value.self)
        isInitialized = true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension LogField: Equatable where Value: Equatable {}
extension LogField: Hashable where Value: Hashable {}
