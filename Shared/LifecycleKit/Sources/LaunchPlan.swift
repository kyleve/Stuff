/// The typed launch (or teardown) tree: a sequential *trunk* of required
/// steps plus concurrent *detached* fan-outs.
///
/// `Input` is what the plan's root step needs (`Void` for a launch; a
/// teardown plan roots at a real value, e.g. the session being torn down).
/// `Output` is the trunk value after the last node — the proof the whole
/// launch is done, carried into `LifecycleRunner.Phase.ready`. `ID` is the
/// plan's identity domain, inferred from its root step — a typed enum per
/// plan (Where uses `LaunchStepID`) rather than a bare `String`.
///
/// The combinators make invalid plans unrepresentable:
/// - `then` requires the next step's `Input` to equal the current trunk
///   `Output` — a step cannot be placed before its input exists.
/// - every combinator requires the node's `ID` to equal the plan's, so one
///   plan can't mix identity domains and a node keyed for another plan can't
///   be composed in.
/// - `thenKeeping` and `gate` are pass-through (`Void`-output step / no
///   transformation), so they are the only trunk positions that may be
///   mode-gated or conditional: skipping them cannot leave a hole in the
///   data flow.
/// - `detached` children take the trunk value and return `Void`, so nothing
///   downstream can depend on a fire-and-forget step.
///
/// Types are erased *inside* the plan (one place, `LaunchPlanNode`), so the
/// runner can memoize heterogeneous outputs and re-walk the trunk on a
/// promotion; the combinators' constraints guarantee every internal cast.
@MainActor
public struct LaunchPlan<ID: Hashable & Sendable, Input: Sendable, Output: Sendable> {
    /// The erased node list the runner walks. Order is trunk order; detached
    /// groups occupy one position and fan out from there.
    package private(set) var nodes: [LaunchPlanNode]

    /// The plan's node IDs in declaration order (detached children at their
    /// group's position) — introspection for tests and tooling.
    ///
    /// Recovers `ID` from the erased nodes; every node was appended by a
    /// combinator constrained to `S.ID == ID`, so the cast can't fail (the
    /// same guarantee the trunk-value casts rely on).
    public var nodeIDs: [ID] {
        nodes.flatMap(\.ids).map { $0.base as! ID }
    }

    private init(nodes: [LaunchPlanNode]) {
        self.nodes = nodes
    }

    /// Root the plan at `step`. The plan's `ID`/`Input`/`Output` are inferred
    /// from the step, so a launch plan starts `LaunchPlan(OpenStoreStep(...))`
    /// and a teardown plan roots at the value it consumes.
    public init<S: LifecycleStep>(_ step: S)
        where S.Input == Input, S.Output == Output, S.ID == ID
    {
        self.init(nodes: [])
        append(.step(StepNode(producing: step)))
    }

    /// Root the plan at `gate`, so the first thing a launch does is wait for
    /// the user — the shape an app takes when nothing may be built until a
    /// choice is made (which account to open, whether to run against real
    /// data at all). Everything the gate's resolution decides is then built by
    /// the steps after it.
    ///
    /// A gate transforms nothing, so the plan's `Input` and `Output` are its
    /// `Value`: rooting here can't leave a hole in the data flow the way a
    /// skippable *producing* step would. In practice that means `Void`, since
    /// a launch plan's root input is `Void` — the gate parks, and the step
    /// after it mints the first real value.
    ///
    /// Note the default `modes` of `.foreground`, which skips a gate on a
    /// headless launch and re-evaluates it on promotion. A root gate whose job
    /// is to stop a headless launch from building anything wants `.all`
    /// instead: parking is exactly the desired outcome there (see
    /// ``LifecycleGate/modes-swift.property``).
    public init<G: LifecycleGate>(_ gate: G)
        where G.Value == Input, G.Value == Output, G.ID == ID
    {
        self.init(nodes: [])
        append(.gate(GateNode(erasing: gate)))
    }

    /// Run `step` after the trunk so far, its `Input` fed by the current
    /// trunk `Output`; the trunk value becomes the step's output. Required
    /// semantics: a throw fails the drive terminally — the recovery for a
    /// failed launch is relaunching the app, not resuming here.
    public func then<S: LifecycleStep>(_ step: S) -> LaunchPlan<ID, Input, S.Output>
        where S.Input == Output, S.ID == ID
    {
        LaunchPlan<ID, Input, S.Output>(nodes: nodes)
            .appending(.step(StepNode(producing: step)))
    }

    /// Run a required `Void`-output step and keep the trunk value flowing
    /// past it. Because the value is untouched, this is the one trunk *step*
    /// position that may be mode-gated (`modes`) — a skipped step here can't
    /// break the data flow.
    public func thenKeeping<S: LifecycleStep>(_ step: S) -> LaunchPlan<ID, Input, Output>
        where S.Input == Output, S.Output == Void, S.ID == ID
    {
        appending(.step(StepNode(keeping: step)))
    }

    /// Park the trunk at `gate` when it applies (`modes`) and is needed
    /// (`isNeeded`), awaiting external resolution through a
    /// `LifecycleGateHandle`. Pass-through by construction — see
    /// `LifecycleGate`.
    public func gate<G: LifecycleGate>(_ gate: G) -> LaunchPlan<ID, Input, Output>
        where G.Value == Output, G.ID == ID
    {
        appending(.gate(GateNode(erasing: gate)))
    }

    /// Fan `children` out concurrently from this trunk position. Children
    /// take the trunk value, return nothing, and cannot present or fail the
    /// drive: a failure surfaces on `LifecycleRunner.detachedFailures` (and
    /// never blocks `.ready`). The trunk continues immediately with its value
    /// unchanged.
    public func detached(
        @DetachedChildrenBuilder<ID, Output> _ children: @MainActor ()
            -> [DetachedChild<ID, Output>],
    ) -> LaunchPlan<ID, Input, Output> {
        appending(.detached(children().map(\.node)))
    }

    private func appending(_ node: LaunchPlanNode) -> Self {
        var copy = self
        copy.append(node)
        return copy
    }

    /// Node IDs must be unique within a plan: run-once memoization and
    /// gate-view registration both key on them, so a duplicate would make
    /// those ambiguous. A duplicate is a programmer
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
public struct DetachedChild<ID: Hashable & Sendable, Value: Sendable> {
    let node: DetachedNode

    public init<S: LifecycleStep>(_ step: S)
        where S.Input == Value, S.Output == Void, S.ID == ID
    {
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
public enum DetachedChildrenBuilder<ID: Hashable & Sendable, Value: Sendable> {
    public static func buildExpression<S: LifecycleStep>(_ step: S) -> [DetachedChild<ID, Value>]
        where S.Input == Value, S.Output == Void, S.ID == ID
    {
        [DetachedChild(step)]
    }

    public static func buildExpression(_ child: DetachedChild<ID, Value>)
        -> [DetachedChild<ID, Value>]
    {
        [child]
    }

    public static func buildBlock(_ children: [DetachedChild<ID, Value>]...)
        -> [DetachedChild<ID, Value>]
    {
        children.flatMap(\.self)
    }

    public static func buildOptional(_ children: [DetachedChild<ID, Value>]?)
        -> [DetachedChild<ID, Value>]
    {
        children ?? []
    }

    public static func buildEither(first children: [DetachedChild<ID, Value>])
        -> [DetachedChild<ID, Value>]
    {
        children
    }

    public static func buildEither(second children: [DetachedChild<ID, Value>])
        -> [DetachedChild<ID, Value>]
    {
        children
    }

    public static func buildArray(_ children: [[DetachedChild<ID, Value>]])
        -> [DetachedChild<ID, Value>]
    {
        children.flatMap(\.self)
    }

    public static func buildLimitedAvailability(
        _ children: [DetachedChild<ID, Value>],
    ) -> [DetachedChild<ID, Value>] {
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
