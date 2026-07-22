# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic engine that runs app startup (and its
reverse, teardown) as an **ordinary async function**: data flows through
`let`s, conditionality through `if`s, and a `LifecycleContext` provides the
`step`/`gate`/`detached` wrappers that add phase publication, run-once
memoization, and failure attribution. A `@MainActor @Observable`
`LifecycleRunner<Launch>` drives the function and publishes one
value-carrying `phase`. Rendering lives in
[LifecycleKitUI](../LifecycleKitUI/AGENTS.md). See [`README.md`](README.md)
for the full narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **Foundation + Observation**. It must **not** import SwiftUI, UIKit,
  WhereCore, or any app code — views belong in LifecycleKitUI; app-specific
  launch logic lives in the consumer (e.g. `WhereUI/Sources/Launch/`).
- The context and the engine are `@MainActor`; heavy work hops to an actor
  *inside* a step's body, never by loosening isolation.

## Invariants

- **Effects live inside `step`/`gate`/`detached` — never in bare glue.** A
  promotion re-drive re-runs the *whole function* with the memo skipping
  completed steps, so unwrapped code between steps re-runs. Glue is value
  plumbing and `if`s only. This is the function style's load-bearing
  convention; don't add a code path that relies on glue running once.
- **Failure is terminal.** A thrown step parks `.failed` with no retry — the
  recovery is relaunching the app. A failed teardown likewise parks and does
  not relaunch (a thrown erase leaves state intact). Don't reintroduce a
  resume/retry path; if a launch step is genuinely flaky, retry inside the
  step at the layer that understands the failure.
- **One step ID, one call site.** The memo keys on IDs: a duplicate within a
  walk traps on any complete run; a memo hit with a mismatched type traps
  with the offending ID. The memo exists only for promotion; teardown runs
  once through a throwaway store and may share IDs with the launch.
- **Only `Void` work may gate on the launch reason** — held by API shape
  (the value-producing `step` overload has no `modes:`), not a runtime check.
  Skipped steps and gates are unmemoized, so they re-evaluate when a
  promotion re-runs the function.
- **All drives funnel through a single in-flight task** (cancel-and-drain):
  two drives never overlap, and `teardown()`/`enterForeground()` can
  interrupt a launch parked on a gate. A cancelled drive is distinct from a
  thrown step (`.failed`); a superseded drive never writes the phase the new
  drive owns, and its gate handle resolves to a no-op. Detached work is
  cancelled when its drive is superseded and always drained before the drive
  task completes — and before a teardown's relaunch. Don't add a drive path
  that bypasses that serialization.
- **Detached work is off the critical path by construction:** `Void` bodies,
  never blocks `.ready`, failures only on `detachedFailures`.
- **Promotion is foreground-only and idempotent.** `enterForeground()` no-ops
  for a foreground launch; consumers must only call it once the scene is
  genuinely `.active` (see `RootView` in WhereUI for the `scenePhase` gating
  pattern).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests
build launch functions inline (steps are closures; `FixtureGate` is the one
shared fixture) and assert on `phase` and the `@_spi(Testing)`
`executedStepIDs` recording; seeded fuzz tests
(`LifecycleRunnerFuzzTests`) build randomized functions and replay failures
exactly against an independent model. Keep tests deterministic — park async
steps on test-controlled streams/handles, not timing.
