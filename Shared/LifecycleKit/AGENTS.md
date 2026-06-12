# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic SwiftUI microframework that models app startup
(and its reverse, reset/teardown) as an ordered, conditional,
launch-reason-aware sequence of async steps. A `@MainActor @Observable`
`Launcher` walks the sequence and publishes one `phase`; `LaunchContainer`
renders it. See [`README.md`](README.md) for the full narrative and usage.

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
*inside* a step's `run`, so there are no `Sendable` gymnastics on the step
itself.

- [`Launcher`](Sources/Launcher.swift) – the engine. Runs the synchronous
  `prelude` at `init`, then `run()` walks the steps, filtering by
  `reason`/`modes` and the async `condition`, awaiting each body. A throw parks
  it in `.failed`; `retry()` resumes from the failed step; `enterForeground()`
  promotes a headless launch; `reset(_:)` runs a teardown sequence then
  re-drives from the top. **All drives funnel through a single `runTask`** and
  await any in-flight drive before starting a new one — don't add a drive path
  that bypasses that serialization.
- [`LaunchStep`](Sources/LaunchStep.swift) – one unit of work: `id`,
  `allowedModes`, async `condition`, `run`, optional `presentation`. Chained
  modifiers (`.when` / `.modes` / `.presenting{,(when:),(after:)}`) return
  copies. Built via the `Work` / `Interactive` free functions. `Interactive`
  defaults to `.modes(.foreground)` so it can't deadlock a headless launch.
- [`LaunchSequence` / `LaunchBuilder`](Sources/LaunchSequence.swift) – a
  result builder (`if`/`if-else`/`for`) collecting steps; declaration order is
  run order. `steps` is public so consumers can parity-test the order.
- [`StepHandle`](Sources/StepHandle.swift) – the bridge to a step's presented
  view. `progress`/`message`/`presentation` are observable; interactive steps
  suspend on `waitForResolution()` and the view calls `complete()`/`fail(_:)`.
  Resolving *before* a caller waits is buffered (`earlyResolution`) so there's
  no lost-wakeup race — preserve that if you touch it.
- [`LaunchReason` / `LaunchModeSet` / `BackgroundCause`](Sources/LaunchReason.swift)
  – why the app launched and which steps that allows. `reason.modeSet` is the
  single bit a step's `allowedModes` must contain.
- [`LaunchPhase` / `LaunchFailure`](Sources/LaunchPhase.swift) – the observable
  state the host renders, plus `isLaunching`/`isReady`/`runningStepID`/
  `runningHandle`/`failure` accessors (handy in tests).
- [`LaunchContainer`](Sources/LaunchContainer.swift) – the root view. Renders
  `splash` / a step's presentation / [`LaunchFailureView`](Sources/LaunchFailureView.swift)
  / `content` from `phase`. The destination (`content`, e.g. the app's
  `TabView`) is **not** a step — it's terminal and shown only at `.ready`.
- [`LaunchSplash`](Sources/LaunchSplash.swift) – the default placeholder.

## Two invariants to preserve

- **Background launches build no view tree.** `LaunchContainer` returns
  `EmptyView()` whenever `launcher.reason.isBackground` — even at `.ready` — so
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
  hop to an actor or a detached task inside `run`, not by loosening isolation
  on the step.
- Every previewable view here ships a `#Preview` (see `LaunchSplash`,
  `LaunchFailureView`, `LaunchContainer`).

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only, never XCTest). The bundle
runs in `StuffTestHost`. Patterns:

- Engine behavior ([`LauncherTests`](Tests/LauncherTests.swift),
  [`LauncherResetTests`](Tests/LauncherResetTests.swift)): build a
  `LaunchSequence`, run the `Launcher`, assert on `phase`. For an interactive
  step, drive `run()` from a `Task` and poll `launcher.phase` until it parks on
  the expected step, then resolve via `runningHandle`.
- View behavior ([`LaunchContainerTests`](Tests/LaunchContainerTests.swift)):
  host through `StuffTestHost` and assert which branch renders per phase /
  reason (splash, presentation, failure, content, `EmptyView`).
- Keep tests deterministic: gate async steps behind a test-controlled
  continuation rather than racing real timing.
