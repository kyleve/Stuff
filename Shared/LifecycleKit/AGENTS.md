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
- **Only pass-through positions may skip.** Value-producing (`init`/`then`)
  steps must keep `modes == .all` (plan-construction `precondition`) — a
  skipped producer would leave a hole in the data flow. Don't add a skip path
  for them.
- **All drives funnel through a single in-flight task** (cancel-and-drain):
  two drives never overlap, and `teardown()`/`enterForeground()` can
  interrupt a launch parked on a gate. A cancelled drive is distinct from a
  thrown node (`.failed`), a superseded drive never writes the phase the new
  drive owns, and a superseded drive's gate handle resolves to a no-op.
  Don't add a drive path that bypasses that serialization.
- **Memoized run-once, per attempt.** Completed nodes' outputs are memoized;
  `retry()` resumes the failed node with its original input and promotion
  never repeats completed work. Skipped gates are deliberately *not*
  memoized so they re-evaluate on promotion. Fresh attempts (first `run()`,
  post-teardown relaunch) clear the memo.
- **Detached children are off the critical path by construction:** they never
  block `.ready`, never fail the drive, and surface failures only on
  `detachedFailures`. A successful teardown releases the retained teardown
  plan + input (the input is typically the dead session).
- **Promotion is foreground-only and idempotent.** `enterForeground()` no-ops
  for a foreground launch; consumers must only call it once the scene is
  genuinely `.active` (see `RootView` in WhereUI for the `scenePhase` gating
  pattern).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests
build a `LaunchPlan` from the shared `FixtureStep`/`FixtureGate` fixtures and
assert on `phase`; seeded fuzz tests (`LifecycleRunnerFuzzTests`) replay
failures exactly against an independent model. Keep tests deterministic —
park async steps on test-controlled streams/handles, not timing.
