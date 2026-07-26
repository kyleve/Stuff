# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic engine that models app startup (and its
reverse, teardown) as a **typed plan**: steps are types with concrete
`Input`/`Output`, a `LaunchPlan` composes them into a sequential trunk plus
concurrent detached fan-outs with the data flow checked at compile time, and
a `@MainActor @Observable` `LifecycleRunner<Launch>` walks the plan and
publishes one value-carrying `phase`. Rendering lives in
[LifecycleKitUI](../LifecycleKitUI/AGENTS.md). See [`README.md`](README.md)
for the full narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **Foundation + Observation**. It must **not** import SwiftUI, UIKit,
  WhereCore, or any app code — views belong in LifecycleKitUI; app-specific
  launch logic lives in the consumer (e.g. `WhereUI/Sources/Launch/`).
- Steps, gates, and the engine are `@MainActor`; heavy work hops to an actor
  *inside* a step's `run`, never by loosening isolation on the step.

## Invariants

- **The type erasure has exactly one home.** `LaunchPlan`'s combinators erase
  steps into `LaunchPlanNode` (package-visible for the runner and the UI
  proxy seam); their generic constraints guarantee every internal cast. Never
  add a second erasure site or a public API that traffics in `Any`.
- **One identity domain per plan.** `LaunchPlan` is generic over
  `ID: Hashable & Sendable` and every combinator requires the node's
  `ID` to match, so a plan can't mix domains and a node keyed for another
  plan can't be composed in; `nodeIDs` gives back `[ID]`, not erased keys.
  IDs erase to `AnyHashable` *inside* `LaunchPlanNode` and stay erased from
  there on — the runner's memo, `LifecycleFailure.stepID`,
  `LifecycleStepContext.stepID`, and `LifecycleGateHandle.id` are all
  `AnyHashable`, deliberately: `LifecycleDriving` (the seam behind the
  non-generic `\.lifecycle` environment value) traffics in `[LaunchPlanNode]`,
  so pushing `ID` past the plan would force it onto the runner, the container's
  generic list, and every splash/failure/gate closure. If you want typed
  `failed(at:)` / `isRunning(_:)` assertions, that's the (deliberate) cost to
  price in — it isn't an oversight.
- **Only pass-through positions may skip.** Value-producing (`init`/`then`)
  steps must keep `modes == .all` (plan-construction `precondition`) — a
  skipped producer would leave a hole in the data flow. Don't add a skip path
  for them.
- **Failure is terminal.** A thrown node parks `.failed` with no retry — the
  recovery is relaunching the app. A failed teardown likewise parks and does
  not relaunch (a thrown erase leaves state intact). Don't reintroduce a
  resume/retry path; if a node is genuinely flaky, retry inside it at the
  layer that understands the failure.
- **All drives funnel through a single in-flight task** (cancel-and-drain):
  two drives never overlap, and `teardown()`/`enterForeground()` can
  interrupt a launch parked on a gate. A cancelled drive is distinct from a
  thrown node (`.failed`), a superseded drive never writes the phase the new
  drive owns, and a superseded drive's gate handle resolves to a no-op.
  Don't add a drive path that bypasses that serialization.
- **Memoized run-once, for promotion.** Completed nodes' outputs are
  memoized so an `enterForeground()` promotion's re-walk skips completed
  work; skipped gates are deliberately *not* memoized so they re-evaluate on
  promotion. Fresh attempts (first `run()`, the start of a teardown, the
  post-teardown relaunch) clear the memo — so teardown plans may freely reuse
  launch node IDs (no live shared memo, since there is no retry re-walk).
- **Detached children are off the critical path by construction:** they never
  block `.ready`, never fail the drive, and surface failures only on
  `detachedFailures`.
- **`.undetermined` is the honest UIScene launch reason.** Under the UIScene
  lifecycle `UIApplication.applicationState` reads `.background` at
  `didFinishLaunching` even for a user tap, so a consumer that can't yet tell a
  headless wake from a user launch should launch `.undetermined` rather than
  fabricate a `.background(cause)`. It gates to the background-safe nodes and
  builds no view tree until `enterForeground()` promotes it; if no scene ever
  connects it honestly stays `.undetermined`, never claiming a cause it didn't
  observe.
- **Promotion resolves a not-yet-foreground launch and is idempotent.**
  `enterForeground()` no-ops once the reason *is* `.userForeground`, so a
  repeat call costs nothing while `.background` and `.undetermined` both
  promote; consumers must only call it once the scene is genuinely `.active`
  (see `RootView` in WhereUI for the `scenePhase` gating pattern).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests
build a `LaunchPlan` from the shared `FixtureStep`/`FixtureGate` fixtures and
assert on `phase`; seeded fuzz tests (`LifecycleRunnerFuzzTests`) replay
failures exactly against an independent model. Keep tests deterministic —
park async steps on test-controlled streams/handles, not timing.
