/// The typed launch (or teardown) tree: a sequential *trunk* of required
/// steps plus concurrent *detached* fan-outs.
///
/// `Input` is what the plan's root step needs (`Void` for a launch; a
/// teardown plan roots at a real value, e.g. the session being torn down).
/// `Output` is the trunk value after the last node — the proof the whole
/// launch is done, carried into `LifecycleRunner.Phase.ready`.
///
/// The combinators make invalid plans unrepresentable:
/// - `then` requires the next step's `Input` to equal the current trunk
///   `Output` — a step cannot be placed before its input exists.
/// - `thenKeeping` and `gate` are pass-through (`Void`-output step / no
///   transformation), so they are the only trunk positions that may be
///   mode-gated or conditional: skipping them cannot leave a hole in the
///   data flow.
/// - `detached` children take the trunk value and return `Void`, so nothing
///   downstream can depend on a fire-and-forget step.
///
/// Types are erased *inside* the plan (one place, `LaunchPlanNode`), so the
/// runner can memoize heterogeneous outputs and resume a retry mid-trunk; the
/// combinators' constraints guarantee every internal cast.
@MainActor
public struct LaunchPlan<Input: Sendable, Output: Sendable> {
    /// The erased node list the runner walks. Order is trunk order; detached
    /// groups occupy one position and fan out from there.
    package private(set) var nodes: [LaunchPlanNode]

    /// The plan's node IDs in declaration order (detached children at their
    /// group's position) — introspection for tests and tooling.
    public var nodeIDs: [AnyHashable] {
        nodes.flatMap(\.ids)
    }

    private init(nodes: [LaunchPlanNode]) {
        self.nodes = nodes
    }

    /// Root the plan at `step`. The plan's `Input`/`Output` are inferred from
    /// the step, so a launch plan starts `LaunchPlan(OpenStoreStep(...))` and
    /// a teardown plan roots at the value it consumes.
    public init<S: LifecycleStep>(_ step: S) where S.Input == Input, S.Output == Output {
        self.init(nodes: [])
        append(.step(StepNode(producing: step)))
    }

    /// Run `step` after the trunk so far, its `Input` fed by the current
    /// trunk `Output`; the trunk value becomes the step's output. Required
    /// semantics: a throw fails the drive, and `retry()` resumes here with
    /// the memoized upstream value.
    public func then<S: LifecycleStep>(_ step: S) -> LaunchPlan<Input, S.Output>
        where S.Input == Output
    {
        LaunchPlan<Input, S.Output>(nodes: nodes)
            .appending(.step(StepNode(producing: step)))
    }

    /// Run a required `Void`-output step and keep the trunk value flowing
    /// past it. Because the value is untouched, this is the one trunk *step*
    /// position that may be mode-gated (`modes`) — a skipped step here can't
    /// break the data flow.
    public func thenKeeping<S: LifecycleStep>(_ step: S) -> LaunchPlan<Input, Output>
        where S.Input == Output, S.Output == Void
    {
        appending(.step(StepNode(keeping: step)))
    }

    /// Park the trunk at `gate` when it applies (`modes`) and is needed
    /// (`isNeeded`), awaiting external resolution through a
    /// `LifecycleGateHandle`. Pass-through by construction — see
    /// `LifecycleGate`.
    public func gate<G: LifecycleGate>(_ gate: G) -> LaunchPlan<Input, Output>
        where G.Value == Output
    {
        appending(.gate(GateNode(erasing: gate)))
    }

    /// Fan `children` out concurrently from this trunk position. Children
    /// take the trunk value, return nothing, and cannot present or fail the
    /// drive: a failure surfaces on `LifecycleRunner.detachedFailures` (and
    /// never blocks `.ready`). The trunk continues immediately with its value
    /// unchanged.
    public func detached(
        @DetachedChildrenBuilder<Output> _ children: @MainActor () -> [DetachedChild<Output>],
    ) -> LaunchPlan<Input, Output> {
        appending(.detached(children().map(\.node)))
    }

    private func appending(_ node: LaunchPlanNode) -> Self {
        var copy = self
        copy.append(node)
        return copy
    }

    /// Node IDs must be unique within a plan: retry resumption, run-once
    /// memoization, and gate-view registration all key on them, so a
    /// duplicate would make those ambiguous. A duplicate is a programmer
    /// error — fail fast at plan construction.
    private mutating func append(_ node: LaunchPlanNode) {
        var seen = Set(nodes.flatMap(\.ids))
        for id in node.ids {
            precondition(
                seen.insert(id).inserted,
                "LaunchPlan contains duplicate node ID: \(id)",
            )
        }
        nodes.append(node)
    }
}

/// A fire-and-forget child of a `LaunchPlan.detached` group, erased over the
/// step that backs it. Constructed only from steps whose `Input` is the trunk
/// value and whose `Output` is `Void`, so a detached step that produces a
/// value anyone could depend on is unspellable.
@MainActor
public struct DetachedChild<Value: Sendable> {
    let node: DetachedNode

    public init<S: LifecycleStep>(_ step: S) where S.Input == Value, S.Output == Void {
        node = DetachedNode(
            id: step.id,
            modes: step.modes,
            run: { @Sendable value, context in
                try await step.run(value as! S.Input, context)
            },
        )
    }
}

/// Result builder for `LaunchPlan.detached`, with `if`/`if-else`/`for`
/// support so children can be included conditionally. Bare steps are lifted
/// into `DetachedChild`, which is where the `Input == Value, Output == Void`
/// constraints live.
@resultBuilder
@MainActor
public enum DetachedChildrenBuilder<Value: Sendable> {
    public static func buildExpression<S: LifecycleStep>(_ step: S) -> [DetachedChild<Value>]
        where S.Input == Value, S.Output == Void
    {
        [DetachedChild(step)]
    }

    public static func buildExpression(_ child: DetachedChild<Value>) -> [DetachedChild<Value>] {
        [child]
    }

    public static func buildBlock(_ children: [DetachedChild<Value>]...) -> [DetachedChild<Value>] {
        children.flatMap(\.self)
    }

    public static func buildOptional(_ children: [DetachedChild<Value>]?)
        -> [DetachedChild<Value>]
    {
        children ?? []
    }

    public static func buildEither(first children: [DetachedChild<Value>])
        -> [DetachedChild<Value>]
    {
        children
    }

    public static func buildEither(second children: [DetachedChild<Value>])
        -> [DetachedChild<Value>]
    {
        children
    }

    public static func buildArray(_ children: [[DetachedChild<Value>]]) -> [DetachedChild<Value>] {
        children.flatMap(\.self)
    }

    public static func buildLimitedAvailability(
        _ children: [DetachedChild<Value>],
    ) -> [DetachedChild<Value>] {
        children
    }
}

// MARK: - Erased nodes

/// One erased position on a plan's trunk. This is the single place the typed
/// step/gate generics are erased; the `LaunchPlan` combinators' constraints
/// guarantee every `as!` inside the erased closures succeeds, so the runner
/// never sees a cast fail and the public API never shows `Any`.
package enum LaunchPlanNode {
    case step(StepNode)
    case gate(GateNode)
    case detached([DetachedNode])

    /// Every ID this node contributes to the plan's uniqueness domain.
    var ids: [AnyHashable] {
        switch self {
            case let .step(node): [node.id]
            case let .gate(node): [node.id]
            case let .detached(children): children.map(\.id)
        }
    }
}

/// A required trunk step, erased. `run` returns the trunk value after the
/// node: the step's output for a value-producing step, the untouched input
/// for a `thenKeeping` step.
package struct StepNode {
    package let id: AnyHashable
    package let modes: LifecycleModeSet
    package let run: @Sendable @MainActor (
        any Sendable,
        LifecycleStepContext,
    ) async throws -> any Sendable

    /// Erase a value-producing (`init`/`then`) step. Such a step can never be
    /// skipped — a skip would leave a hole in the data flow — so it must not
    /// narrow `modes`; a narrowed one is a misconfiguration, caught here at
    /// plan construction.
    @MainActor
    init<S: LifecycleStep>(producing step: S) {
        precondition(
            step.modes == .all,
            """
            Step '\(step.id)' produces a value, so it must run under all modes \
            (modes: .all); only pass-through positions (thenKeeping, gates, \
            detached children) may gate on the launch reason.
            """,
        )
        id = step.id
        modes = step.modes
        run = { @Sendable value, context in
            try await step.run(value as! S.Input, context)
        }
    }

    /// Erase a pass-through (`thenKeeping`) step: the step's `Void` output is
    /// discarded and the input keeps flowing.
    @MainActor
    init<S: LifecycleStep>(keeping step: S) where S.Output == Void {
        id = step.id
        modes = step.modes
        run = { @Sendable value, context in
            try await step.run(value as! S.Input, context)
            return value
        }
    }
}

/// A gate on the trunk, erased. The runner evaluates `isNeeded` with the
/// current trunk value and, when true, parks awaiting a `LifecycleGateHandle`
/// resolution; `gateType` lets the UI layer's registry recover the gate's
/// concrete type (and with it `Value`) statically.
package struct GateNode {
    package let id: AnyHashable
    package let modes: LifecycleModeSet
    package let gateType: ObjectIdentifier
    package let isNeeded: @Sendable @MainActor (any Sendable) async -> Bool

    @MainActor
    init<G: LifecycleGate>(erasing gate: G) {
        id = gate.id
        modes = gate.modes
        gateType = ObjectIdentifier(G.self)
        isNeeded = { @Sendable value in
            await gate.isNeeded(value as! G.Value)
        }
    }
}

/// A detached child, erased. Runs concurrently with the trunk; its failure is
/// recorded, never fatal.
package struct DetachedNode {
    package let id: AnyHashable
    package let modes: LifecycleModeSet
    package let run: @Sendable @MainActor (any Sendable, LifecycleStepContext) async throws -> Void
}
