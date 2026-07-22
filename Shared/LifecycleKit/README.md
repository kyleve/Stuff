# LifecycleKit

A small, app-agnostic SwiftUI microframework that models **app startup — and
its reverse, reset/teardown — as an ordered, conditional, launch-reason-aware
sequence of async steps**, driven by a `@MainActor @Observable` engine whose
single published `phase` the root view renders.

It replaces the usual scattering of launch logic (a synchronous `bootstrap()`
in the app delegate, an async `start()` on a model, a second `start()` from a
view's `.task`) with one linear, inspectable flow. A thrown error bubbles up to
a failure phase with retry; logout/erase is the same machinery run in reverse.

LifecycleKit depends only on SwiftUI + Foundation + Observation — no app code.

## Mental model

Launch is a pipeline. The engine awaits each step in order; advancing to the
next step just moves the cursor, and a thrown error short-circuits to `.failed`.

```
launching ──▶ running ──▶ running ──▶ … ──▶ ready
                 │                            ▲
                 └──▶ failed ──(retry)────────┘

ready ──(teardown)──▶ launching ──▶ … ──▶ ready
```

The key insight that unifies silent and interactive steps: **an interactive
step is just an async step that awaits a continuation the presented UI
resumes.** Onboarding and migration aren't special engine cases — they're steps
whose `perform` suspends on `bridge.waitForResolution()` while their
`presentation` view is shown, and the view calls `bridge.complete()`.

## Installation

`LifecycleKit` is a local SPM library in this repo (`Shared/LifecycleKit`). Add
it to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourUI", dependencies: [.target(name: "LifecycleKit")])
```

## Core API

```swift
// Why we're launching — gates UI-bearing steps. `.undetermined` is the honest
// state under the UIScene lifecycle, where `applicationState` can't tell a user
// launch from a headless wake at launch: it behaves like a background launch
// until `enterForeground()` promotes it once a scene actually activates.
public enum LifecycleReason { case userForeground, background(LifecycleBackgroundCause), undetermined }
public struct LifecycleModeSet: OptionSet { /* .foreground, .background, .all */ }

// One unit of launch work. `condition`/`modes` are set at construction (init /
// .work / .interactive parameters); attach UI with the .presenting modifiers.
public struct LifecycleStep: Identifiable {
    public init(id: AnyHashable, modes: LifecycleModeSet = .all,
                condition: @escaping @MainActor () async -> Bool = { true },
                perform: ...)
    public func presenting(minVisible: Duration = .zero, _ view: ...) -> Self            // always while running
    public func presenting(when: ..., minVisible: Duration = .zero, _ view: ...) -> Self // only if predicate holds at start
    public func presenting(after: Duration, minVisible: Duration = .zero, _ view: ...) -> Self // only if still running after delay
    // minVisible (any trigger): once shown, keep the view up at least this long

    public static func work(_ id: AnyHashable, modes: ... = .all, condition: ... = …, _ perform: ...) -> LifecycleStep
    public static func interactive(_ id: AnyHashable, modes: ... = .foreground, condition: ... = …, perform: ... = …, presenting: ...) -> LifecycleStep
}

@resultBuilder public enum LifecycleStepsBuilder {}              // if / if-else / for
public struct LifecycleSteps { public init(@LifecycleStepsBuilder _ steps: () -> [LifecycleStep]) }

// Bridge between a running step and its presented view.
@MainActor @Observable public final class LifecycleStepUIBridge {
    public let reason: LifecycleReason
    public var progress: Double?      // determinate progress for the view
    public var message: String?
    public func complete()            // UI resumes the step
    public func fail(_ error: Error)  // UI fails the step
    public func waitForResolution() async throws
}

public enum LifecyclePhase {
    case launching, running(LifecycleStep, LifecycleStepUIBridge), failed(LifecycleFailure), ready
}

@MainActor @Observable public final class LifecycleRunner {
    public private(set) var phase: LifecyclePhase
    public init(reason: LifecycleReason,
                initializePrerequisites: @MainActor () -> Void = {},
                sequence: LifecycleSteps)
    public func run() async             // walk the steps; idempotent
    public func retry()                 // re-run from the failed step
    public func enterForeground() async // promote a background/undetermined launch
    public func teardown(_ sequence: LifecycleSteps) async // reverse flow → relaunch
}
```

Steps are built with the `LifecycleStep.work` / `LifecycleStep.interactive`
factories so sequences read declaratively:

```swift
LifecycleStep.work(_ id: AnyHashable,
    modes: LifecycleModeSet = .all,
    condition: @escaping @MainActor () async -> Bool = { true },
    _ perform: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void)
LifecycleStep.interactive(_ id: AnyHashable,
    modes: LifecycleModeSet = .foreground,
    condition: @escaping @MainActor () async -> Bool = { true },
    perform: @escaping @MainActor (LifecycleStepUIBridge) async throws -> Void = { try await $0.waitForResolution() },
    @ViewBuilder presenting: @escaping @MainActor (LifecycleStepUIBridge) -> some View)
```

`LifecycleStep.interactive` defaults to `modes: .foreground`: a step whose
whole job is to wait for the user would deadlock during a headless background
launch (there's no UI to resolve it), so it's skipped there.

## Where the *final* app UI comes from

The launch sequence is only the **prerequisites**. The destination — the real,
"logged-in" / default app UI — is **not a step**; it's the `content` closure
handed to `LifecycleContainer`, rendered when (and only when) the runner reaches
`.ready`. (It can't be a step: steps complete and the cursor advances, whereas
the app UI is terminal and persists for the rest of the process lifetime.)

```swift
LifecycleContainer(runner) {      // `content` == the real app, the destination
    MainTabView()                 // appears once the runner hits .ready
}
```

`LifecycleContainer` renders from `runner.phase`:

| phase | renders |
|-------|---------|
| `.launching` / a silent step | `splash()` (defaults to `LifecycleSplash`) |
| `.running` with a presentation | that step's view (onboarding, migration) |
| `.failed` | `failure(_:retry:)` (defaults to `LifecycleFailureView`) |
| `.ready` | `content()` — the destination UI |

Surfaces crossfade by default (see `transition`/`animation` below).

The `splash` and `failure` views are caller-injectable; the convenience
initializers above default them to the built-ins.

Surface changes (splash → failure → app `content`) are animated. The designated
initializer takes `transition`/`animation` (a crossfade by default; pass
`animation: nil` to swap instantly):

```swift
LifecycleContainer(runner, transition: .opacity, animation: .easeInOut) {
    MainTabView()
}
```

The transition is keyed on `LifecyclePhase.surfaceIdentity`, which collapses
`.launching` and `.running` into one "splash" surface so a step *advancing* —
still showing the splash — doesn't retrigger the transition and flash it; only
reaching `.failed`/`.ready` animates.

The launch surfaces (splash / step presentation / failure) are layered **above**
`content`. When the runner reaches `.ready` the leaving splash plays its
*removal* transition over the entering destination — so a reveal that scales the
splash up and fades it out uncovers the app UI beneath, rather than being
clipped to a pop behind freshly-inserted content:

```swift
LifecycleContainer(
    runner,
    transition: .asymmetric(insertion: .identity,
                            removal: .scale(scale: 16).combined(with: .opacity)),
    animation: .easeIn(duration: 0.55),
    splash: { LaunchSplashView() },
) { MainTabView() }
```

The container also publishes the runner into the environment as
`\.lifecycleRunner`, a `LifecycleRunnerProxy` (not a bare optional), letting
nested views reach `retry()`/`teardown()` without prop-drilling. When no
container is above (previews, isolated tests) the proxy is *disconnected* and
each call asserts in debug / no-ops in release, so call sites never `guard`:

```swift
struct ResetButton: View {
    @Environment(\.lifecycleRunner) private var runner
    var body: some View {
        Button("Erase & reset", role: .destructive) {
            Task { await runner.teardown(teardownSteps) }
        }
    }
}
```

For a launch that shows no window (`reason.buildsNoViewTree` — a **background**
relaunch, or an **undetermined** one not yet promoted) it renders `EmptyView()`
always — even at `.ready` — so `content()` (the heavy view tree) is never built.

## Usage

Build the runner early (e.g. in the app delegate, so a headless background
launch works before any window exists) and drive it:

```swift
// App delegate / launch site:
let runner = LifecycleRunner(
    // Under the UIScene lifecycle `applicationState` reads `.background` even
    // for a user tap, so don't guess a cause here: launch `.undetermined` and
    // let `enterForeground()` promote it when a scene actually activates.
    reason: .undetermined,
    initializePrerequisites: { deps.installLocationManager() }, // synchronous, must-exist-now wiring
    sequence: LifecycleSteps {
        LifecycleStep.work("open-store") { _ in try await deps.openStore() }
            // Migration UI keyed off slowness: shown only if the open is still
            // running after a beat, then held for a readable minimum.
            .presenting(after: .milliseconds(500), minVisible: .seconds(1)) {
                MigrationProgressView(bridge: $0)
            }

        LifecycleStep.interactive("onboarding", condition: { !deps.hasOnboarded }) {
            OnboardingView(bridge: $0)
        }

        LifecycleStep.work("sync-auth")          { _ in await deps.syncAuthorization() }
        LifecycleStep.work("reconcile-tracking") { _ in await deps.reconcileTracking() }
        LifecycleStep.work("load")               { _ in await deps.refresh() }
    },
)
Task { await runner.run() }
```

```swift
// Root view: gate the real app behind the runner.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    let runner: LifecycleRunner

    var body: some View {
        LifecycleContainer(runner) { MainTabView() }
            // run() is idempotent; promote a background launch only once the
            // scene is genuinely active, so a background-connected scene stays
            // headless.
            .task {
                await runner.run()
                if scenePhase == .active { await runner.enterForeground() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await runner.enterForeground() }
            }
    }
}
```

### Reset / teardown

Run a reverse sequence and relaunch from the top — e.g. a logout/erase that
returns the app to first-run onboarding once teardown clears the "has onboarded"
flag:

```swift
Button("Erase all data & reset", role: .destructive) {
    Task {
        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("erase")  { _ in try await deps.eraseAll() }
            LifecycleStep.work("forget") { _ in deps.resetPreferences() }
        })
    }
}
```

If a teardown step throws, the runner parks in `.failed` and does **not**
relaunch; `retry()` resumes the teardown from the failed step, then relaunches.

## Two correctness points designed in deliberately

- **Synchronous `initializePrerequisites` vs. async steps.**
  `initializePrerequisites` runs synchronously at `init` for cheap,
  must-exist-now wiring (e.g. installing a `CLLocationManager` delegate a queued
  background event can't wait for). Everything expensive — including opening a
  store that may run a slow migration — belongs in an async step, so it never
  blocks `didFinishLaunching` (and the system watchdog).

- **Windowless launches build no UI.** iOS connects a background scene without
  displaying it and reclaims such apps first under memory pressure, so a launch
  with no window should build *no* view tree. `LifecycleContainer` enforces this
  (`EmptyView()` whenever `reason.buildsNoViewTree` — a `.background` relaunch or
  an `.undetermined` one not yet promoted); the work still runs because it's
  driven from the launch site (`Task { await runner.run() }`), independent of
  whether SwiftUI ever builds the hierarchy. When a window genuinely appears,
  `enterForeground()` promotes the runner and re-drives so foreground-only
  steps (onboarding) now run — skipping any step that already completed during
  the windowless drive, so a work step never runs twice.

All drives (`run` / `enterForeground` / `retry` / `teardown`) are serialized
through a single internal task, so two never overlap (which would let, e.g., a
store-open step run twice concurrently). A new drive **cancels** the in-flight
one and awaits it draining before starting: a parked interactive step's
`waitForResolution()` throws `CancellationError`, which the engine treats as
"drive cancelled" (stop quietly), distinct from a step throwing (→ `.failed`).
That's what lets `teardown()` / `enterForeground()` interrupt a launch parked on
onboarding instead of hanging forever behind it.

## Testing

The engine and views are exercised with Swift Testing + a hosted UI test host.
What's worth covering when adopting it: step ordering, `condition` gating, mode
filtering (background skips foreground-only), thrown error → `.failed` +
`retry()` resuming from the failed step, interactive suspension until
`bridge.complete()`, progress propagation, and `teardown()` returning to
`.launching`. Because a real interactive step suspends, drive it from a `Task`
and poll `runner.phase` until it parks, then resolve the bridge.
