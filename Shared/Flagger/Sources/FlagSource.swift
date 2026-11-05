/// A module-owned collection of explicitly registered feature-flag groups.
public protocol FlagSource: Sendable {
    static var id: FlagSourceID { get }
    static var name: String { get }
    static var groups: FeatureFlagGroupRegistry { get }
}

public struct FlagSourceID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A flag source ID must not be empty.")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct FeatureFlagSourceMetadata: Identifiable, Hashable, Sendable {
    public let id: FlagSourceID
    public let name: String
}
