# LifecycleKit

A small, app-agnostic engine that models **app startup — and its reverse,
reset/teardown — as a typed plan**: a sequential trunk of required steps plus
concurrent detached fan-outs, driven by a `@MainActor @Observable` runner
whose single published `phase` the UI layer renders.

Each step is its own type with concrete `Input`/`Output`. The plan's
combinators check the data flow at compile time, so the classic launch bugs —
a step running before the thing it needs exists, a skipped step leaving a
hole downstream, the app UI rendering off an optional that "should" have been
set — are unrepresentable rather than merely avoided. A thrown trunk step
parks the runner in a failure phase with retry; logout/erase is the same
machinery run over a teardown plan.

LifecycleKit depends only on Foundation + Observation — **no SwiftUI, no app
code**. Everything rendered lives in [LifecycleKitUI](../LifecycleKitUI).

## Mental model

Launch is a typed pipeline. The trunk value at any point is the launch's
*dependency scope so far* — the proof of everything promoted to that point —
and it only grows, by each step embedding what came before:

```
            trunk (required, ordered, typed)                      detached fan
┌──────────┐   ┌───────────────┐   ┌──────────┐   ┌───────────┐  ┌──────────┐
│ OpenStore ├──▶│ StartSession ├──▶│ gate:     ├──▶│ SyncAuth  ├─┬▶ Reminders │
│ Void→Svcs │   │ Svcs→Session │   │Onboarding│   │ (keeping) │ ├▶ Widgets   │ …
└──────────┘   └───────────────┘   └──────────┘   └───────────┘ └▶ …
                                                        │
                                              .ready(Session) — before the fan drains
```

- **`then` steps** produce the next scope; their `Input` must equal the
  current trunk `Output`, so misordering is a compile error. They can never
  be skipped (the plan `precondition`s `modes == .all` for them) — a skipped
  producer would leave a hole in the data flow.
- **`thenKeeping` steps** are required `Void`-output work; the trunk value
  flows past them, so they *may* gate on the launch reason.
- **Gates** park the trunk awaiting external (user) resolution — onboarding
  is the canonical one. Pass-through by construction, foreground-only by
  default, re-evaluated when a headless launch is promoted.
- **Detached children** take the trunk value and return `Void`, so nothing
  can depend on a fire-and-forget step. They run concurrently, never block
  `.ready`, and a failure lands on the runner's `detachedFailures`
  diagnostics — observable, never fatal.

## Installation

`LifecycleKit` is a local SPM library in this repo (`Shared/LifecycleKit`).
Add it to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourCore", dependencies: [.target(name: "LifecycleKit")])
```

## Core API

```swift
// One unit of launch/teardown work. Input is what it needs; Output is what
// finishing proves.
@MainActor public protocol LifecycleStep {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    var id: AnyHashable { get }             // a typed enum case, ideally
    var modes: LifecycleModeSet { get }     // defaults to .all
    func run(_ input: Input, _ context: LifecycleStepContext) async throws -> Output
}

// A trunk node that parks the drive awaiting external resolution.
// Pass-through by construction; foreground-only by default.
@MainActor public protocol LifecycleGate {
    associatedtype Value: Sendable
    var id: AnyHashable { get }
    var modes: LifecycleModeSet { get }     // defaults to .foreground
    func isNeeded(_ value: Value) async -> Bool
}

// The typed tree. Input is the root step's input (Void for a launch; a real
// value for a teardown), Output the trunk's final value.
@MainActor public struct LaunchPlan<Input: Sendable, Output: Sendable> {
    public init<S: LifecycleStep>(_ step: S) where S.Input == Input, S.Output == Output
    public func then<S>(_ step: S) -> LaunchPlan<Input, S.Output> where S.Input == Output
    public func thenKeeping<S>(_ step: S) -> Self where S.Input == Output, S.Output == Void
    public func gate<G: LifecycleGate>(_ gate: G) -> Self where G.Value == Output
    public func detached(@DetachedChildrenBuilder<Output> _ children: ...) -> Self
    public var nodeIDs: [AnyHashable]       // introspection for tests/tools
}

// The engine, generic over the launch's output.
@MainActor @Observable public final class LifecycleRunner<Launch: Sendable> {
    public enum Phase {
        case launching                          // splash
        case running(LifecycleStepContext)      // splash + caption/progress
        case awaitingGate(LifecycleGateHandle)  // the gate's registered view
        case failed(LifecycleFailure)           // failure UI + retry
        case ready(Launch)                      // the app, handed the launch's output
    }
    public private(set) var phase: Phase
    public private(set) var detachedFailures: [LifecycleFailure] // off-phase diagnostics
    public init(reason: LifecycleReason,
                initializePrerequisites: @MainActor () -> Void = {},
                plan: LaunchPlan<Void, Launch>)
    public func run() async                 // walk the plan; idempotent
    public func retry()                     // resume from the failed node, same input
    public func enterForeground() async     // promote a background/undetermined launch
    public func teardown<In>(_ plan: LaunchPlan<In, some Sendable>, input: In) async
}

// The engine-minted token for one parked gate — the only way to resume it.
@MainActor public final class LifecycleGateHandle {
    public let id: AnyHashable
    public func complete()
    public func fail(_ error: Error)
}
```

`LifecycleReason` (`.userForeground` / `.background(cause)` / `.undetermined`)
and `LifecycleModeSet` gate which nodes run: `.undetermined` is the honest
state under the UIScene lifecycle, where `applicationState` can't tell a user
launch from a headless wake — it behaves like a background launch until
`enterForeground()` promotes it once a scene actually activates.

## Usage

Model each step as a type; assemble the plan; build the runner early (e.g. in
the app delegate, so a headless background launch works before any window
exists) and drive it:

```swift
struct OpenStoreStep: LifecycleStep {
    let deps: Dependencies
    let id: AnyHashable = StepID.openStore
    func run(_: Void, _: LifecycleStepContext) async throws -> Services {
        try await deps.openStore()          // the process's ONE store open
    }
}

struct StartSessionStep: LifecycleStep {
    let id: AnyHashable = StepID.startSession
    func run(_ services: Services, _: LifecycleStepContext) async throws -> Session {
        Session(services: services)         // scope grows by embedding
    }
}

struct OnboardingGate: LifecycleGate {
    let deps: Dependencies
    let id: AnyHashable = StepID.onboarding
    func isNeeded(_: Session) async -> Bool { !deps.hasOnboarded }
}

let plan = LaunchPlan(OpenStoreStep(deps: deps))
    .then(StartSessionStep())
    .gate(OnboardingGate(deps: deps))
    .thenKeeping(SyncAuthStep())            // required, ordered, Void-output
    .detached {                             // concurrent; never blocks .ready
        RemindersStep()
        WidgetSnapshotStep()
    }

let runner = LifecycleRunner(
    reason: .undetermined,
    initializePrerequisites: { deps.installLocationManager() }, // sync, must-exist-now
    plan: plan,
)
Task { await runner.run() }
```

What the compiler now refuses:

```swift
LaunchPlan(StartSessionStep())              // ✗ needs Services; nothing produced it yet
plan.detached { StartSessionStep() }        // ✗ detached children must be Void-output
LaunchPlan(OpenStoreStep(deps: deps))
    .gate(OnboardingGate(deps: deps))       // ✗ the gate's Value is Session, not Services
```

Rendering — the phase-to-surface mapping, gate-view registration, and the
`\.lifecycle` environment proxy — lives in
[LifecycleKitUI](../LifecycleKitUI/README.md).

### Reset / teardown

A teardown plan roots at a real value (the thing being torn down), runs its
nodes, then relaunches from the top as a fresh attempt — e.g. a logout/erase
that returns the app to first-run onboarding once teardown clears the "has
onboarded" flag:

```swift
await runner.teardown(
    LaunchPlan(EraseDataStep(deps: deps))       // Session → Void
        .then(ResetPreferencesStep(deps: deps)),
    input: session,
)
```

If a teardown node throws, the runner parks in `.failed` and does **not**
relaunch; `retry()` resumes the teardown from the failed node, then
relaunches. A teardown's detached children drain *before* the relaunch, so no
torn-down-world work overlaps the fresh launch. On success the retained plan
and input are released (the input is typically the dead session).

Teardown node IDs must not reuse launch node IDs — the run-once memo is keyed
by ID across both walks, so a collision would silently skip the teardown node
and corrupt the typed trunk value. The runner `precondition`s disjointness
when a teardown is requested (use one ID enum for both plans, as Where's
`LaunchStepID` does, and the collision is impossible to write twice).

## Correctness points designed in deliberately

- **Retry resumes with the same input.** Every completed node's output is
  memoized for the current attempt; `retry()` re-runs the failed node with
  the value it originally got, and nodes that already completed never run
  twice — across `retry()` *and* `enterForeground()` promotion. A fresh
  attempt (first `run()`, the relaunch after a teardown) clears the memo.
- **Skipping can't corrupt the data flow.** Only pass-through positions
  (`thenKeeping`, gates, detached children) may be mode-gated or
  conditional; a skipped gate is *not* memoized, so `isNeeded` re-evaluates
  when the launch is promoted (a cold `.undetermined` start still onboards
  once it becomes user-visible).
- **`.ready` never waits for the fan, and the fan can't regress it.**
  `.ready(Launch)` publishes the moment the trunk finishes; detached children
  drain behind it and report failures only on `detachedFailures`.
- **Drives never overlap.** All drives (`run` / `enterForeground` / `retry`
  / `teardown`) serialize through a single internal task; a new drive cancels
  the in-flight one and awaits it draining first. A parked gate's wait throws
  `CancellationError` on cancellation — "drive cancelled" (stop quietly) is
  distinct from a node throwing (→ `.failed`) — which is what lets
  `teardown()` / `enterForeground()` interrupt a launch parked on onboarding
  instead of hanging forever behind it. A superseded drive that throws a
  *real* error reports cancelled rather than clobbering the phase the new
  drive owns, and a superseded drive's gate handle resolves to a no-op.
- **Synchronous `initializePrerequisites` vs. async steps.** It runs
  synchronously at `init` for cheap, must-exist-now wiring (e.g. installing a
  `CLLocationManager` delegate a queued background event can't wait for).
  Everything expensive — including opening a store that may run a slow
  migration — belongs in an async step, so it never blocks
  `didFinishLaunching` (and the system watchdog).

## Testing

The engine is exercised with Swift Testing: targeted suites for ordering,
value threading, mode gating, gates, detached isolation, promotion, retry
memoization, and teardown — plus seeded fuzz suites that drive randomized
plans against an independent model (200 seeds) and drain randomized flaky
failures through `retry()` (120 seeds). Because a real gate suspends, drive
the runner from a `Task` and poll `runner.phase` until it parks, then resolve
the handle. `@_spi(Testing) injectFailureForTesting(_:)` covers the
failed-with-no-resume-point path.
