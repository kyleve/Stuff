/// Editor-facing state for one registered flag.
public struct FlagSnapshot: Identifiable, Equatable, Sendable {
    public let id: FlagID
    public let name: String
    public let detail: String?
    public let source: FeatureFlagSourceMetadata
    public let group: FeatureFlagGroupMetadata
    public let behavior: FeatureFlagBehaviorKind
    public let defaultValue: JSONValue
    public let storedValue: JSONValue?
    public let effectiveValue: JSONValue
    public let isFrozen: Bool
    public let failure: FlaggerFailure?

    public var isDefault: Bool {
        storedValue == nil
    }

    public var hasPendingChange: Bool {
        isFrozen && (storedValue ?? defaultValue) != effectiveValue
    }
}
