/// One unit of launch (or teardown) work, modeled as its own type with
/// concrete inputs and outputs.
///
/// `Input` is what the step needs to run; `Output` is what finishing proves.
/// A step cannot be scheduled before something upstream has produced its
/// `Input` — the ordering of a `LaunchPlan` is checked by the compiler through
/// these associated types, not by declaration order alone. Cross-step data
/// flows through the plan's trunk value; steps never reach into shared
/// mutable state to find what an earlier step "should have" set.
///
/// Steps are `@MainActor`: heavy work should be delegated to actors from
/// inside `run`, keeping the step itself on the main actor so it can touch
/// main-actor state directly.
@MainActor
public protocol LifecycleStep {
    /// What this step needs. Produced by the plan's upstream trunk (or, for a
    /// plan's root step, supplied by the caller — `Void` for a launch).
    associatedtype Input: Sendable
    /// What finishing this step proves. `Void` for side-effect-only steps.
    associatedtype Output: Sendable
    /// The identity domain this step belongs to — a typed enum per plan (e.g.
    /// Where's `LaunchStepID`) rather than a bare `String`. A `LaunchPlan` is
    /// generic over this, so every node in one plan must share it: a step
    /// keyed in another plan's domain can't be composed in.
    associatedtype ID: Hashable & Sendable

    /// Stable identity used for run-once memoization and tests. Unique within
    /// its plan, which `LaunchPlan` `precondition`s at construction.
    var id: ID { get }

    /// Which launch reasons this step runs under. Read once, when the plan is
    /// built. Only pass-through positions may gate: `LaunchPlan.thenKeeping`
    /// steps and detached children may narrow this (e.g. `.foreground`);
    /// value-producing steps (`LaunchPlan.init` / `then`) must keep the
    /// default `.all` — a skipped step there would leave a hole in the data
    /// flow, and the plan `precondition`s against it.
    var modes: LifecycleModeSet { get }

    /// The step's async work. Throwing from a trunk step fails the drive and
    /// parks the runner in `.failed`; throwing from a detached child only
    /// surfaces on `LifecycleRunner.detachedFailures`.
    func run(_ input: Input, _ context: LifecycleStepContext) async throws -> Output
}

extension LifecycleStep {
    public var modes: LifecycleModeSet {
        .all
    }
}

/// A trunk node that can park the drive awaiting external (user) resolution —
/// first-run onboarding is the canonical example.
///
/// A gate is pass-through by construction: it never transforms the trunk
/// value, so skipping it (mode gating, or `isNeeded` returning false) cannot
/// leave a hole in the data flow. The engine parks in
/// `LifecycleRunner.Phase.awaitingGate` and hands the UI a
/// `LifecycleGateHandle`; the gate's view (registered in the UI layer by gate
/// *type*) resolves the handle to resume — or fail — the drive. The gate type
/// itself carries no view, keeping the engine free of UI.
@MainActor
public protocol LifecycleGate {
    /// The trunk value at this gate's position, passed through untouched.
    associatedtype Value: Sendable
    /// The gate's identity domain — the plan's, same as `LifecycleStep.ID`.
    associatedtype ID: Hashable & Sendable

    /// Stable identity used for run-once memoization and tests. Same
    /// conventions as `LifecycleStep.id`.
    var id: ID { get }

    /// Which launch reasons this gate applies to. Defaults to `.foreground`:
    /// a gate's whole job is to wait for the user, which would park a
    /// headless launch forever, so it is skipped there and re-evaluated when
    /// `enterForeground()` promotes the launch.
    ///
    /// A gate that guards work a headless launch must not do anyway — one
    /// rooting a plan, where nothing may be built until the user chooses —
    /// should declare `.all` instead. Parking forever is then the point: no
    /// later node runs, nothing is built, and the parked drive is superseded
    /// when a scene promotes the launch.
    var modes: LifecycleModeSet { get }

    /// Whether the gate needs to present at all, evaluated when the trunk
    /// reaches it. `false` skips the gate and `value` flows through untouched
    /// — and is re-evaluated on a later re-drive (e.g. after promotion), so a
    /// gate skipped headless still shows once the launch is user-visible.
    func isNeeded(_ value: Value) async -> Bool
}

extension LifecycleGate {
    public var modes: LifecycleModeSet {
        .foreground
    }
}
