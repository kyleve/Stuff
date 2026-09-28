import Foundation

/// A typed feature-flag definition stored as a property on a ``FeatureFlagGroup``.
public struct Flag<Value: Codable & Sendable, Behavior: FeatureFlagBehavior>: Sendable {
    public let id: FlagID
    public let name: String
    public let detail: String?
    public let defaultValue: Value

    public init(
        _ id: FlagID,
        name: String,
        detail: String? = nil,
        default defaultValue: Value,
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.defaultValue = defaultValue
    }

    public init(
        _ id: String,
        name: String,
        detail: String? = nil,
        default defaultValue: Value,
    ) {
        self.init(FlagID(rawValue: id), name: name, detail: detail, default: defaultValue)
    }
}

protocol AnyFeatureFlag: Sendable {
    func definition(
        source: FeatureFlagSourceMetadata,
        group: FeatureFlagGroupMetadata,
    ) throws -> FlagDefinition
}

extension Flag: AnyFeatureFlag {
    func definition(
        source: FeatureFlagSourceMetadata,
        group: FeatureFlagGroupMetadata,
    ) throws -> FlagDefinition {
        try FlagDefinition(
            flag: self,
            source: source,
            group: group,
        )
    }
}
