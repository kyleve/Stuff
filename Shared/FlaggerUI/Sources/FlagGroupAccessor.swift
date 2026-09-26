import Flagger

/// A type-safe, dynamically accessed view of one registered feature-flag group.
@MainActor
@dynamicMemberLookup
public struct FlagGroupAccessor<Group: FeatureFlagGroup> {
    private let group: Group
    private let model: FlaggerModel

    init(group: Group, model: FlaggerModel) {
        self.group = group
        self.model = model
    }

    public subscript<Value>(
        dynamicMember keyPath: KeyPath<Group, Flag<Value, some FeatureFlagBehavior>>,
    ) -> Value where Value: Codable & Sendable {
        model.value(for: group[keyPath: keyPath])
    }

    public func value<Value: Codable & Sendable>(
        for keyPath: KeyPath<Group, Flag<Value, some FeatureFlagBehavior>>,
    ) throws -> Value {
        try model.throwingValue(for: group[keyPath: keyPath])
    }

    public func set<Value: Codable & Sendable>(
        _ value: Value,
        for keyPath: KeyPath<Group, Flag<Value, LiveUpdating>>,
    ) async throws {
        try await model.set(value, for: group[keyPath: keyPath])
    }

    public func reset(
        _ keyPath: KeyPath<Group, Flag<some Codable & Sendable, LiveUpdating>>,
    ) async throws {
        try await model.reset(group[keyPath: keyPath])
    }
}
