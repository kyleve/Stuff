/// Stable persisted identity for a feature flag.
public struct FlagID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A flag ID must not be empty.")
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}
