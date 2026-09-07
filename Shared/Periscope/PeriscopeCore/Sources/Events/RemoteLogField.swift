import Foundation

/// A named event field explicitly approved for remote diagnostic export.
public struct RemoteLogField: Equatable, Sendable {
    public let key: RemoteLogFieldKey
    public let value: RemoteLogFieldValue

    public init(key: RemoteLogFieldKey, value: RemoteLogFieldValue) {
        self.key = key
        self.value = value
    }

    /// The standard closed category identifying one case of an event enum.
    public static func eventKind<Value>(_ value: Value) -> Self
        where Value: RawRepresentable & CaseIterable & Sendable, Value.RawValue == String
    {
        Self(
            key: RemoteLogFieldKey("kind"),
            value: .category(RemoteLogCategory(value)),
        )
    }
}

/// A structured remote-field key. Unlike a dictionary key, this keeps event
/// declarations at typed call sites and makes accidental payload export visible.
public struct RemoteLogFieldKey: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: StaticString) {
        self.rawValue = String(describing: rawValue)
    }
}

/// Values deliberately restricted to operational data that cannot carry free-form text.
public enum RemoteLogFieldValue: Equatable, Sendable {
    case boolean(Bool)
    case count(Int)
    case durationMilliseconds(Double)
    case category(RemoteLogCategory)
}

/// A closed enum value approved by an event for remote export.
public struct RemoteLogCategory: Equatable, Sendable {
    public let rawValue: String

    public init<Value>(_ value: Value)
        where Value: RawRepresentable & CaseIterable & Sendable, Value.RawValue == String
    {
        precondition(
            Value.allCases.contains { $0.rawValue == value.rawValue },
            "Remote log categories must be members of a closed CaseIterable set",
        )
        rawValue = value.rawValue
    }
}
