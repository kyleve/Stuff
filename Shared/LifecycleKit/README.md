# LifecycleKit

A small, app-agnostic engine that models **app startup — and its reverse, reset/teardown — as a typed plan**.
The plan has a sequential trunk of required steps plus concurrent detached fan-outs.
A `@MainActor @Observable` runner drives it.
The UI layer renders its single published `phase`.

Each step is its own type with concrete `Input`/`Output`.
The plan's combinators check the data flow at compile time.
The classic launch bugs are unrepresentable rather than merely avoided:
a step running before the thing it needs exists, a skipped step leaving a hole downstream, the app UI rendering off an optional that must have been set.
A thrown trunk step parks the runner in a terminal failure phase (no retry — the recovery is relaunching the app).
Logout/erase is the same machinery run over a teardown plan.

LifecycleKit depends only on Foundation + Observation — **no SwiftUI, no app code**.
Everything rendered lives in [LifecycleKitUI](../LifecycleKitUI).

## Mental model

Launch is a typed pipeline.
The trunk value at any point is the launch's *dependency scope so far* — the proof of everything promoted to that point — and it only grows, by each step embedding what came before:

```
            trunk (required, ordered, typed)                      detached fan
┌──────────┐   ┌───────────────┐   ┌──────────┐   ┌───────────┐  ┌──────────┐
│ OpenStore ├──▶│ StartSession ├──▶│ gate:     ├──▶│ SyncAuth  ├─┬▶ Reminders │
│ Void→Svcs │   │ Svcs→Session │   │Onboarding│   │ (keeping) │ ├▶ Widgets   │ …
└──────────┘   └───────────────┘   └──────────┘   └───────────┘ └▶ …
                                                        │
                                              .ready(Session) — before the fan drains
```

- **`then` steps** produce the next scope.
  Their `Input` must equal the current trunk `Output`, so misordering is a compile error.
  They can never be skipped (the plan `precondition`s `modes == .all` for them) — a skipped producer would leave a hole in the data flow.
- **`thenKeeping` steps** are required `Void`-output work.
  The trunk value flows past them, so they *may* gate on the launch reason.
- **Gates** park the trunk awaiting external (user) resolution — onboarding is the canonical one.
  Pass-through by construction, foreground-only by default, re-evaluated when a headless launch is promoted.
  A plan may also be *rooted* at one, when nothing may be built until the user chooses (see [Rooting a plan at a gate](#rooting-a-plan-at-a-gate)).
- **Detached children** take the trunk value and return `Void`, so nothing can depend on a fire-and-forget step.
  They run concurrently, never block `.ready`, and a failure lands on the runner's `detachedFailures` diagnostics — observable, never fatal.

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
    associatedtype ID: Hashable & Sendable  // the plan's identity domain
    var id: ID { get }                      // a typed enum case
    var modes: LifecycleModeSet { get }     // defaults to .all
    func run(_ input: Input, _ context: LifecycleStepContext) async throws -> Output
}

// A trunk node that parks the drive awaiting external resolution.
// Pass-through by construction; foreground-only by default.
@MainActor public protocol LifecycleGate {
    associatedtype Value: Sendable
    associatedtype ID: Hashable & Sendable
    var id: ID { get }
    var modes: LifecycleModeSet { get }     // defaults to .foreground
    func isNeeded(_ value: Value) async -> Bool
}

// The typed tree. ID is the plan's identity domain (inferred from the root
// step), Input the root step's input (Void for a launch; a real value for a
// teardown), Output the trunk's final value.
@MainActor public struct LaunchPlan<ID: Hashable & Sendable, Input: Sendable, Output: Sendable> {
    public init<S: LifecycleStep>(_ step: S)
    public init<G: LifecycleGate>(_ gate: G)   // root at a gate: Input == Output == Value
        where S.Input == Input, S.Output == Output, S.ID == ID
    public func then<S>(_ step: S) -> LaunchPlan<ID, Input, S.Output>
        where S.Input == Output, S.ID == ID
    public func thenKeeping<S>(_ step: S) -> Self
        where S.Input == Output, S.Output == Void, S.ID == ID
    public func gate<G: LifecycleGate>(_ gate: G) -> Self where G.Value == Output, G.ID == ID
    public func detached(@DetachedChildrenBuilder<ID, Output> _ children: ...) -> Self
    public var nodeIDs: [ID]                // introspection for tests/tools
}

// The engine, generic over the launch's output.
@MainActor @Observable public final class LifecycleRunner<Launch: Sendable> {
    public enum Phase {
        case launching                          // splash
        case running(LifecycleStepContext)      // splash + caption/progress
        case awaitingGate(LifecycleGateHandle)  // the gate's registered view
        case failed(LifecycleFailure)           // terminal failure UI (no retry)
        case ready(Launch)                      // the app, handed the launch's output
    }
    public private(set) var phase: Phase
    public private(set) var detachedFailures: [LifecycleFailure] // off-phase diagnostics
    public init(reason: LifecycleReason,
                initializePrerequisites: @MainActor () -> Void = {},
                plan: LaunchPlan<some Hashable & Sendable, Void, Launch>)
    public func run() async                 // walk the plan; idempotent
    public func enterForeground() async     // promote a background/undetermined launch
    public func teardown<In>(_ plan: LaunchPlan<some Hashable & Sendable, In, some Sendable>,
                             input: In) async
}

// The engine-minted token for one parked gate — the only way to resume it.
@MainActor public final class LifecycleGateHandle {
    public let id: AnyHashable
    public func complete()
    public func fail(_ error: Error)
}
```

`LifecycleReason` (`.userForeground` / `.background(cause)` / `.undetermined`) and `LifecycleModeSet` gate which nodes run.
`.undetermined` is the honest state under the UIScene lifecycle, where `applicationState` cannot tell a user launch from a headless wake.
It behaves like a background launch until `enterForeground()` promotes it once a scene actually activates.

## Usage

Model each step as a type.
Assemble the plan.
Build the runner early (e.g. in the app delegate, so a headless background launch works before any window exists) and drive it:

```swift
struct OpenStoreStep: LifecycleStep {
    let deps: Dependencies
    let id = StepID.openStore
    func run(_: Void, _: LifecycleStepContext) async throws -> Services {
        try await deps.openStore()          // the process's ONE store open
    }
}

struct StartSessionStep: LifecycleStep {
    let id = StepID.startSession
    func run(_ services: Services, _: LifecycleStepContext) async throws -> Session {
        Session(services: services)         // scope grows by embedding
    }
}

struct OnboardingGate: LifecycleGate {
    let deps: Dependencies
    let id = StepID.onboarding
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

### Rooting a plan at a gate

Some apps must build *nothing* until the user chooses — which account to open, or whether to run against real data at all.
Root the plan at the gate, and let the steps after it build whatever the choice decided:

```swift
struct ChooseModeGate: LifecycleGate {
    let deps: Deps
    let id = StepID.chooseMode
    // Not the `.foreground` default: parking a headless launch here is the
    // point — nothing downstream runs, so nothing is built for a launch the
    // user hasn't chosen a world for yet.
    let modes: LifecycleModeSet = .all
    func isNeeded(_: Void) async -> Bool { deps.activeScope == nil }
}

let plan = LaunchPlan(ChooseModeGate(deps: deps))   // Void → Void
    .then(ResolveScopeStep(deps: deps))             // Void → Scope
    .then(StartSessionStep())                       // Scope → Session
```

A gate transforms nothing, so rooting at one cannot leave a hole in the data flow the way a skippable producing step would.
The plan's `Input` and `Output` are the gate's `Value`, which for a launch means `Void`.
Since a gate carries no value, whatever the user chose reaches the next step through the dependencies it was built with, not through the trunk.

Rendering — the phase-to-surface mapping, gate-view registration, and the `\.lifecycle` environment proxy — lives in [LifecycleKitUI](../LifecycleKitUI/README.md).

### Reset / teardown

A teardown plan roots at a real value (the thing being torn down), runs its nodes, then relaunches from the top as a fresh attempt — e.g. a logout/erase that returns the app to first-run onboarding once teardown clears the "has onboarded" flag:

```swift
await runner.teardown(
    LaunchPlan(EraseDataStep(deps: deps))       // Session → Void
        .then(ResetPreferencesStep(deps: deps)),
    input: session,
)
```

If a teardown node throws, the runner parks in the terminal `.failed` and does **not** relaunch.
A thrown erase never reaches the session drop, so state stays intact and relaunching the app returns to the working app rather than a half-erased one.
A teardown's detached children drain *before* the relaunch, so no torn-down-world work overlaps the fresh launch.

Teardown starts from an empty run-once set (the launch attempt is over), so a teardown plan may freely reuse launch node IDs.
There is no retry re-walk that would consult a live launch memo, so no cross-plan disjointness precondition is needed.

## Correctness points designed in deliberately

- **Failure is terminal.** A thrown node parks `.failed` with no retry — the recovery is relaunching the app.
  (Retry's original customer, a fresh install's transient store-open race, was fixed structurally by injection.
  Genuinely retryable work belongs to the layer that understands it.)
- **Promotion re-walks with the memo** skipping completed nodes, so completed work never runs twice within an attempt (the memo exists only for promotion — a fresh launch never re-walks a node).
  A fresh attempt (first `run()`, the start of a teardown, the relaunch after it) clears the memo.
- **Skipping cannot corrupt the data flow.** Only pass-through positions (`thenKeeping`, gates, detached children) may be mode-gated or conditional.
  A skipped gate is *not* memoized, so `isNeeded` re-evaluates when the launch is promoted (a cold `.undetermined` start still onboards once it becomes user-visible).
- **`.ready` never waits for the fan, and the fan cannot regress it.**
  `.ready(Launch)` publishes the moment the trunk finishes.
  Detached children drain behind it and report failures only on `detachedFailures`.
- **Drives never overlap.** All drives (`run` / `enterForeground` / `teardown`) serialize through a single internal task.
  A new drive cancels the in-flight one and awaits it draining first.
  A parked gate's wait throws `CancellationError` on cancellation — "drive cancelled" (stop quietly) is distinct from a node throwing (→ `.failed`) — which is what lets `teardown()` / `enterForeground()` interrupt a launch parked on onboarding instead of hanging forever behind it.
  A superseded drive that throws a *real* error reports cancelled rather than clobbering the phase the new drive owns, and a superseded drive's gate handle resolves to a no-op.
- **Synchronous `initializePrerequisites` vs. async steps.** It runs synchronously at `init` for cheap, must-exist-now wiring (e.g. installing a `CLLocationManager` delegate a queued background event cannot wait for).
  Everything expensive — including opening a store that may run a slow migration — belongs in an async step, so it never blocks `didFinishLaunching` (and the system watchdog).

## Testing

The engine is exercised with Swift Testing.
Targeted suites cover ordering, value threading, mode gating, gates, detached isolation, promotion (memo run-once), terminal failure, and teardown (including reusing launch node IDs).
A seeded fuzz suite drives randomized plans against an independent model (200 seeds).
Because a real gate suspends, drive the runner from a `Task` and poll `runner.phase` until it parks, then resolve the handle.
