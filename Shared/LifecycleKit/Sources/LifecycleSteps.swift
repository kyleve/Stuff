/// Result builder that collects `LifecycleStep`s declared in a
/// `LifecycleSteps`, with `if`/`if-else`/`for` support so steps can be
/// included conditionally.
@resultBuilder
public enum LifecycleStepsBuilder {
    public static func buildExpression(_ step: LifecycleStep) -> [LifecycleStep] {
        [step]
    }

    public static func buildExpression(_ steps: [LifecycleStep]) -> [LifecycleStep] {
        steps
    }

    public static func buildBlock(_ components: [LifecycleStep]...) -> [LifecycleStep] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [LifecycleStep]?) -> [LifecycleStep] {
        component ?? []
    }

    public static func buildEither(first component: [LifecycleStep]) -> [LifecycleStep] {
        component
    }

    public static func buildEither(second component: [LifecycleStep]) -> [LifecycleStep] {
        component
    }

    public static func buildArray(_ components: [[LifecycleStep]]) -> [LifecycleStep] {
        components.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ component: [LifecycleStep]) -> [LifecycleStep] {
        component
    }
}

/// An ordered list of lifecycle steps. The engine walks these top to bottom;
/// the declaration order is the run order.
public struct LifecycleSteps {
    public let steps: [LifecycleStep]

    public init(@LifecycleStepsBuilder _ steps: () -> [LifecycleStep]) {
        let steps = steps()
        Self.assertUniqueIDs(steps)
        self.steps = steps
    }

    public init(steps: [LifecycleStep]) {
        Self.assertUniqueIDs(steps)
        self.steps = steps
    }

    /// Step IDs must be unique within a sequence: retry/teardown resume by
    /// matching `LifecycleFailure.stepID` against `step.id`, so a duplicate would
    /// make resumption ambiguous.
    private static func assertUniqueIDs(_ steps: [LifecycleStep]) {
        var seen = Set<AnyHashable>()
        let duplicates = steps.map(\.id).filter { !seen.insert($0).inserted }
        precondition(
            duplicates.isEmpty,
            "LifecycleSteps contains duplicate step IDs: \(duplicates)",
        )
    }
}
