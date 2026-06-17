# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic SwiftUI microframework that models app startup
(and its reverse, teardown) as an ordered, conditional,
launch-reason-aware sequence of async steps. A `@MainActor @Observable`
`LifecycleRunner` walks the sequence and publishes one `phase`;
`LifecycleContainer` renders it. See [`README.md`](README.md) for the full
narrative and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **SwiftUI + Foundation + Observation**. It must **not** import WhereCore,
  UIKit, or any app code — it's a generic library that the Where app (and any
  future app) adopts. Keep it that way: app-specific launch logic lives in the
  consumer (e.g. `WhereUI/Sources/Launch/`), not here.
- Library target only ([`Package.swift`](../../Package.swift),
  `Shared/LifecycleKit/Sources`); the hosted test bundle `LifecycleKitTests`
  is wired in [`Project.swift`](../../Project.swift) via the `unitTests` helper
  (host: `StuffTestHost`).

## Key types

Everything user-facing is `@MainActor`; heavy work is delegated to actors from
*inside* a step's `perform`, so there are no `Sendable` gymnastics on the step
itself.

- [`LifecycleRunner`](Sources/LifecycleRunner.swift) – the engine. Runs the
  synchronous `initializePrerequisites` at `init`, then `run()` walks the steps,
  filtering by `reason`/`modes` and the async `condition`, awaiting each step's
  `perform`. A throw parks it in `.failed`; `retry()` resumes from the failed
  step; `enterForeground()` promotes a headless launch; `teardown(_:)` runs a
  teardown sequence then re-drives from the top — and a teardown step that throws
  parks in `.failed` like any other, so `retry()` resumes the *teardown* from
  there (not the launch) before relaunching. Internal bookkeeping lives in one
  `State` enum so invalid combinations are unrepresentable. **All drives funnel
  through a single in-flight task**: a new drive `cancel()`s the previous one
  and awaits it draining before starting (cancel-and-drain), so two never
  overlap *and* `teardown()`/`enterForeground()` can interrupt a launch parked on
  an interactive step rather than hanging behind it. A cancelled drive ends as
  `DriveOutcome.cancelled` (stop quietly), distinct from a thrown step
  (`.failed`). Don't add a drive path that bypasses that serialization.
- [`LifecycleStep`](Sources/LifecycleStep.swift) – one unit of work: `id`,
  `allowedModes`, async `condition`, `perform`, optional `presentation`. Run
  gating (`modes` / `condition`) is set at construction — init or the
  `LifecycleStep.work` / `LifecycleStep.interactive` factory parameters — while
  UI is attached with chained `.presenting{,(when:),(after:)}` modifiers (each
  taking a `minVisible:` hold) that return copies. `LifecycleStep.interactive`
  defaults to `modes: .foreground` so it can't deadlock a headless launch.
- [`LifecycleSteps` / `LifecycleStepsBuilder`](Sources/LifecycleSteps.swift) – a
  result builder (`if`/`if-else`/`for`) collecting steps; declaration order is
  run order. `steps` is public so consumers can parity-test the order.
- [`LifecycleStepUIBridge`](Sources/LifecycleStepUIBridge.swift) – the bridge to
  a step's presented view. `progress`/`message`/`presentation` are observable;
  interactive steps suspend on `waitForResolution()` and the view calls
  `complete()`/`fail(_:)`. State is one `Resolution` enum (`pending` /
  `resolved(Result)`) so the resolved value and the "has resolved" flag can't
  drift; resolving *before* a caller waits is buffered there (no lost-wakeup
  race) and a second resolution is ignored. `waitForResolution()` is
  cancellation-aware — it throws `CancellationError` when the drive is
  cancelled, which is how the runner drains a parked step. Preserve both if you
  touch it.
- [`LifecycleReason` / `LifecycleModeSet` / `LifecycleBackgroundCause`](Sources/LifecycleReason.swift)
  – why the app launched and which steps that allows. `reason.modeSet` is the
  single bit a step's `allowedModes` must contain.
- [`LifecyclePhase` / `LifecycleFailure`](Sources/LifecyclePhase.swift) – the
  observable state the host renders, plus
  `isLaunching`/`isReady`/`runningStepID`/`runningBridge`/`failure` accessors
  (handy in tests).
- [`LifecycleContainer`](Sources/LifecycleContainer.swift) – the root view.
  Renders `splash` / a step's presentation / `failure` / `content` from
  `phase`. The `splash` and `failure` views are caller-injectable (convenience
  inits default them to [`LifecycleSplash`](Sources/LifecycleSplash.swift) /
  [`LifecycleFailureView`](Sources/LifecycleFailureView.swift)), and the runner
  is published into the environment as `\.lifecycleRunner` (optional) so nested
  views can reach `retry()`/`teardown()`. The destination (`content`, e.g. the
  app's `TabView`) is **not** a step — it's terminal and shown only at `.ready`.
- [`LifecycleSplash`](Sources/LifecycleSplash.swift) – the default placeholder.

## Two invariants to preserve

- **Background launches build no view tree.** `LifecycleContainer` returns
  `EmptyView()` whenever `runner.reason.isBackground` — even at `.ready` — so
  the heavy `content()` is never constructed for a launch nobody sees. The work
  still runs because it's driven from the launch site, not the view. Don't make
  `content` render for a background reason.
- **Promotion is foreground-only and idempotent.** `enterForeground()` no-ops
  unless `reason.isBackground`, then flips `reason` to `.userForeground` and
  re-drives. Consumers must only call it once the scene is genuinely `.active`
  (a background-connected scene may still build the view and run `.task`) — see
  `RootView` in `WhereUI` for the `scenePhase` gating pattern.

## Conventions

- Follow the root rules: exhaustive `switch` over enums (no bare `default:`),
  small named structs over tuples, bind SwiftUI state directly (no closure
  `Binding(get:set:)`).
- Steps and the engine are `@MainActor`; if a step needs heavy/off-main work,
  hop to an actor or a detached task inside `perform`, not by loosening isolation
  on the step.
- Every previewable view here ships a `#Preview` (see `LifecycleSplash`,
  `LifecycleFailureView`, `LifecycleContainer`).

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only, never XCTest). The bundle
runs in `StuffTestHost`. Patterns:

- Engine behavior ([`LifecycleRunnerTests`](Tests/LifecycleRunnerTests.swift),
  [`LifecycleRunnerResetTests`](Tests/LifecycleRunnerResetTests.swift)): build a
  `LifecycleSteps`, run the `LifecycleRunner`, assert on `phase`. For an
  interactive step, drive `run()` from a `Task` and poll `runner.phase` until it
  parks on the expected step, then resolve via `runningBridge`.
- View behavior ([`LifecycleContainerTests`](Tests/LifecycleContainerTests.swift)):
  host through `StuffTestHost` and assert which branch renders per phase /
  reason (splash, presentation, failure, content, `EmptyView`).
- Keep tests deterministic: gate async steps behind a test-controlled
  continuation rather than racing real timing.
