/// An immutable, result-builder-created list of group types exposed by a source.
public struct FeatureFlagGroupRegistry: Sendable {
    let registrations: [FeatureFlagGroupRegistration]

    public init(@FeatureFlagGroupRegistryBuilder _ content: () -> [FeatureFlagGroupRegistration]) {
        registrations = content()
    }
}

public struct FeatureFlagGroupRegistration: Sendable {
    let typeID: ObjectIdentifier
    let metadata: FeatureFlagGroupMetadata
    let make: @Sendable () -> any FeatureFlagGroup

    init<Group: FeatureFlagGroup>(_ type: Group.Type) {
        typeID = ObjectIdentifier(type)
        metadata = FeatureFlagGroupMetadata(id: type.id, name: type.name, detail: type.detail)
        make = { Group() }
    }
}

@resultBuilder
public enum FeatureFlagGroupRegistryBuilder {
    public static func buildExpression(
        _ expression: (some FeatureFlagGroup).Type,
    ) -> [FeatureFlagGroupRegistration] {
        [FeatureFlagGroupRegistration(expression)]
    }

    public static func buildBlock(
        _ components: [FeatureFlagGroupRegistration]...,
    ) -> [FeatureFlagGroupRegistration] {
        components.flatMap(\.self)
    }

    public static func buildOptional(
        _ component: [FeatureFlagGroupRegistration]?,
    ) -> [FeatureFlagGroupRegistration] {
        component ?? []
    }

    public static func buildEither(
        first component: [FeatureFlagGroupRegistration],
    ) -> [FeatureFlagGroupRegistration] {
        component
    }

    public static func buildEither(
        second component: [FeatureFlagGroupRegistration],
    ) -> [FeatureFlagGroupRegistration] {
        component
    }

    public static func buildArray(
        _ components: [[FeatureFlagGroupRegistration]],
    ) -> [FeatureFlagGroupRegistration] {
        components.flatMap(\.self)
    }
}
