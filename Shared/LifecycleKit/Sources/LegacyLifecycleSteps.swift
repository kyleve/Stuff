/// Result builder that collects `LegacyLifecycleStep`s declared in a
/// `LegacyLifecycleSteps`, with `if`/`if-else`/`for` support so steps can be
/// included conditionally.
@resultBuilder
public enum LegacyLifecycleStepsBuilder {
    public static func buildExpression(_ step: LegacyLifecycleStep) -> [LegacyLifecycleStep] {
        [step]
    }

    public static func buildExpression(_ steps: [LegacyLifecycleStep]) -> [LegacyLifecycleStep] {
        steps
    }

    public static func buildBlock(_ components: [LegacyLifecycleStep]...) -> [LegacyLifecycleStep] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [LegacyLifecycleStep]?) -> [LegacyLifecycleStep] {
        component ?? []
    }

    public static func buildEither(first component: [LegacyLifecycleStep])
        -> [LegacyLifecycleStep]
    {
        component
    }

    public static func buildEither(second component: [LegacyLifecycleStep])
        -> [LegacyLifecycleStep]
    {
        component
    }

    public static func buildArray(_ components: [[LegacyLifecycleStep]]) -> [LegacyLifecycleStep] {
        components.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ component: [LegacyLifecycleStep])
        -> [LegacyLifecycleStep]
    {
        component
    }
}

/// An ordered list of lifecycle steps. The engine walks these top to bottom;
/// the declaration order is the run order.
public struct LegacyLifecycleSteps {
    public let steps: [LegacyLifecycleStep]

    public init(@LegacyLifecycleStepsBuilder _ steps: () -> [LegacyLifecycleStep]) {
        let steps = steps()
        Self.assertUniqueIDs(steps)
        self.steps = steps
    }

    public init(steps: [LegacyLifecycleStep]) {
        Self.assertUniqueIDs(steps)
        self.steps = steps
    }

    /// Step IDs must be unique within a sequence: retry/teardown resume by
    /// matching `LifecycleFailure.stepID` against `step.id`, so a duplicate would
    /// make resumption ambiguous.
    private static func assertUniqueIDs(_ steps: [LegacyLifecycleStep]) {
        var seen = Set<AnyHashable>()
        let duplicates = steps.map(\.id).filter { !seen.insert($0).inserted }
        precondition(
            duplicates.isEmpty,
            "LegacyLifecycleSteps contains duplicate step IDs: \(duplicates)",
        )
    }
}
