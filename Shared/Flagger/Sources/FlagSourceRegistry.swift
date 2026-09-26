/// The composition root's explicit list of module-level flag sources.
public struct FlagSourceRegistry: Sendable {
    let types: [any FlagSource.Type]

    public init(@FlagSourceRegistryBuilder _ content: () -> [any FlagSource.Type]) {
        types = content()
    }
}

@resultBuilder
public enum FlagSourceRegistryBuilder {
    public static func buildExpression(
        _ expression: (some FlagSource).Type,
    ) -> [any FlagSource.Type] {
        [expression]
    }

    public static func buildBlock(
        _ components: [any FlagSource.Type]...,
    ) -> [any FlagSource.Type] {
        components.flatMap(\.self)
    }

    public static func buildOptional(
        _ component: [any FlagSource.Type]?,
    ) -> [any FlagSource.Type] {
        component ?? []
    }

    public static func buildEither(
        first component: [any FlagSource.Type],
    ) -> [any FlagSource.Type] {
        component
    }

    public static func buildEither(
        second component: [any FlagSource.Type],
    ) -> [any FlagSource.Type] {
        component
    }

    public static func buildArray(
        _ components: [[any FlagSource.Type]],
    ) -> [any FlagSource.Type] {
        components.flatMap(\.self)
    }
}
