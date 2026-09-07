/// An immutable, result-builder-created list of group types exposed by a source.
public struct FeatureFlagGroupRegistry: Sendable {
    let types: [any FeatureFlagGroup.Type]

    public init(@FeatureFlagGroupRegistryBuilder _ content: () -> [any FeatureFlagGroup.Type]) {
        types = content()
    }
}

@resultBuilder
public enum FeatureFlagGroupRegistryBuilder {
    public static func buildExpression(
        _ expression: (some FeatureFlagGroup).Type,
    ) -> [any FeatureFlagGroup.Type] {
        [expression]
    }

    public static func buildBlock(
        _ components: [any FeatureFlagGroup.Type]...,
    ) -> [any FeatureFlagGroup.Type] {
        components.flatMap(\.self)
    }

    public static func buildOptional(
        _ component: [any FeatureFlagGroup.Type]?,
    ) -> [any FeatureFlagGroup.Type] {
        component ?? []
    }

    public static func buildEither(
        first component: [any FeatureFlagGroup.Type],
    ) -> [any FeatureFlagGroup.Type] {
        component
    }

    public static func buildEither(
        second component: [any FeatureFlagGroup.Type],
    ) -> [any FeatureFlagGroup.Type] {
        component
    }

    public static func buildArray(
        _ components: [[any FeatureFlagGroup.Type]],
    ) -> [any FeatureFlagGroup.Type] {
        components.flatMap(\.self)
    }
}
