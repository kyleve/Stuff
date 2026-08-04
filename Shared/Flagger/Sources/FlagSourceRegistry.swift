/// The composition root's explicit list of module-level flag sources.
public struct FlagSourceRegistry: Sendable {
    let registrations: [FlagSourceRegistration]

    public init(@FlagSourceRegistryBuilder _ content: () -> [FlagSourceRegistration]) {
        registrations = content()
    }
}

public struct FlagSourceRegistration: Sendable {
    let metadata: FeatureFlagSourceMetadata
    let groups: FeatureFlagGroupRegistry

    init(_ type: (some FlagSource).Type) {
        metadata = FeatureFlagSourceMetadata(id: type.id, name: type.name)
        groups = type.groups
    }
}

@resultBuilder
public enum FlagSourceRegistryBuilder {
    public static func buildExpression(
        _ expression: (some FlagSource).Type,
    ) -> [FlagSourceRegistration] {
        [FlagSourceRegistration(expression)]
    }

    public static func buildBlock(
        _ components: [FlagSourceRegistration]...,
    ) -> [FlagSourceRegistration] {
        components.flatMap(\.self)
    }

    public static func buildOptional(
        _ component: [FlagSourceRegistration]?,
    ) -> [FlagSourceRegistration] {
        component ?? []
    }

    public static func buildEither(
        first component: [FlagSourceRegistration],
    ) -> [FlagSourceRegistration] {
        component
    }

    public static func buildEither(
        second component: [FlagSourceRegistration],
    ) -> [FlagSourceRegistration] {
        component
    }

    public static func buildArray(
        _ components: [[FlagSourceRegistration]],
    ) -> [FlagSourceRegistration] {
        components.flatMap(\.self)
    }
}
