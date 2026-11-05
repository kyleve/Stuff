/// A named collection of feature-flag definitions owned by one module source.
public protocol FeatureFlagGroup: Sendable {
    init()
    static var id: FeatureFlagGroupID { get }
    static var name: String { get }
    static var detail: String? { get }
}

extension FeatureFlagGroup {
    public static var detail: String? {
        nil
    }
}

/// Stable identity for a feature-flag group.
public struct FeatureFlagGroupID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A feature-flag group ID must not be empty.")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

public struct FeatureFlagGroupMetadata: Identifiable, Hashable, Sendable {
    public let id: FeatureFlagGroupID
    public let name: String
    public let detail: String?
}

/// The environment-style namespace modules extend with named group accessors.
public struct FeatureFlagGroups: Sendable {
    public init() {}

    public subscript<Group: FeatureFlagGroup>(_: Group.Type) -> Group {
        Group()
    }
}
