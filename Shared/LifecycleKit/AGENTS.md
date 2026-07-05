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
- **Background launches build no view tree.** `LifecycleContainer` returns
  `EmptyView()` whenever `runner.reason.isBackground` — even at `.ready` — so
  `content()` is never constructed for a launch nobody sees.
- **Promotion is foreground-only and idempotent.** `enterForeground()` no-ops
  unless the reason is background; consumers must only call it once the scene
  is genuinely `.active` (see `RootView` in WhereUI for the `scenePhase`
  gating pattern).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests
build a `LifecycleSteps` and assert on `phase`; view tests host
`LifecycleContainer` and assert which branch renders; seeded fuzz tests
(`LifecycleRunnerFuzzTests`) replay failures exactly. Keep tests
deterministic — gate async steps on test-controlled continuations, not timing.
