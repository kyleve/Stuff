/// Omission inherits; an explicit clear removes an optional value.
public enum WhereThemeOptional<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    case clear
    case value(Value)
}
