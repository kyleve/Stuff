# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic SwiftUI microframework that models app startup
(and its reverse, teardown) as an ordered, conditional, launch-reason-aware
sequence of async steps: a `@MainActor @Observable` `LifecycleRunner` walks a
`LifecycleSteps` sequence and publishes one `phase`; `LifecycleContainer`
renders it. See [`README.md`](README.md) for the full narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **SwiftUI + Foundation + Observation**. It must **not** import
  WhereCore, UIKit, or any app code — app-specific launch logic lives in the
  consumer (e.g. `WhereUI/Sources/Launch/`).
- Steps and the engine are `@MainActor`; heavy work hops to an actor *inside*
  a step's `perform`, never by loosening isolation on the step.

## Invariants

- **All drives funnel through a single in-flight task** (cancel-and-drain):
  two drives never overlap, and `teardown()`/`enterForeground()` can interrupt
  a launch parked on an interactive step. A cancelled drive is distinct from a
  thrown step (`.failed`). Don't add a drive path that bypasses that
  serialization.
- **Launches with no window build no view tree.** `LifecycleContainer` returns
  `EmptyView()` whenever `runner.reason.buildsNoViewTree` (a `.background`
  relaunch, or an `.undetermined` one not yet promoted) — even at `.ready` — so
  `content()` is never constructed for a launch nobody sees.
- **`.undetermined` is the honest UIScene launch reason.** Under the UIScene
  lifecycle `UIApplication.applicationState` reads `.background` at
  `didFinishLaunching` even for a user tap, so a consumer that can't yet tell a
  headless wake from a user launch should launch `.undetermined` rather than
  fabricate a `.background(cause)`. It gates to the background-safe steps and
  builds no view tree until `enterForeground()` promotes it; if no scene ever
  connects it honestly stays `.undetermined`, never claiming a cause it didn't
  observe.
- **Promotion resolves a not-yet-foreground launch and is idempotent.**
  `enterForeground()` no-ops unless the reason is already `.userForeground`
  (so `.background` and `.undetermined` both promote); consumers must only call
  it once the scene is genuinely `.active` (see `RootView` in WhereUI for the
  `scenePhase` gating pattern).
- **Each step runs at most once per launch attempt.** A completed step is
  recorded in `completedStepIDs`, and a re-drive (`enterForeground()` promotion)
  skips it — so a work step that already serviced the windowless drive isn't
  repeated when foreground-only steps get their turn. Only steps that actually
  ran to completion are recorded (a mode/condition-skipped or cancelled step
  isn't), so promotion still runs the newly-applicable steps and re-evaluates
  conditions. The set resets on a *fresh* attempt (first `run()`, and the
  relaunch after `teardown()`), so a reset re-runs everything; it's preserved
  across `retry()`, which resumes from the failed step.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests
build a `LifecycleSteps` and assert on `phase`; view tests host
`LifecycleContainer` and assert which branch renders; seeded fuzz tests
(`LifecycleRunnerFuzzTests`) replay failures exactly. Keep tests
deterministic — gate async steps on test-controlled continuations, not timing.
