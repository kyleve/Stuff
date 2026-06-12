/// Result builder that collects `LaunchStep`s declared in a `LaunchSequence`,
/// with `if`/`if-else`/`for` support so steps can be included conditionally.
@resultBuilder
public enum LaunchBuilder {
    public static func buildExpression(_ step: LaunchStep) -> [LaunchStep] {
        [step]
    }

    public static func buildExpression(_ steps: [LaunchStep]) -> [LaunchStep] {
        steps
    }

    public static func buildBlock(_ components: [LaunchStep]...) -> [LaunchStep] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [LaunchStep]?) -> [LaunchStep] {
        component ?? []
    }

    public static func buildEither(first component: [LaunchStep]) -> [LaunchStep] {
        component
    }

    public static func buildEither(second component: [LaunchStep]) -> [LaunchStep] {
        component
    }

    public static func buildArray(_ components: [[LaunchStep]]) -> [LaunchStep] {
        components.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ component: [LaunchStep]) -> [LaunchStep] {
        component
    }
}

/// An ordered list of launch steps. The engine walks these top to bottom; the
/// declaration order is the run order.
public struct LaunchSequence {
    public let steps: [LaunchStep]

    public init(@LaunchBuilder _ steps: () -> [LaunchStep]) {
        self.steps = steps()
    }

    public init(steps: [LaunchStep]) {
        self.steps = steps
    }
}
