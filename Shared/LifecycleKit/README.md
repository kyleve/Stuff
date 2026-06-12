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

Launch is a pipeline. The engine awaits each step in order; a "transition" is
just advancing the cursor, and a thrown error short-circuits to `.failed`.

```
launching ──▶ running ──▶ running ──▶ … ──▶ ready
                 │                            ▲
                 └──▶ failed ──(retry)────────┘

ready ──(reset)──▶ launching ──▶ … ──▶ ready
```

The key insight that unifies silent and interactive steps: **an interactive
step is just an async step that awaits a continuation the presented UI
resumes.** Onboarding and migration aren't special engine cases — they're steps
whose `run` suspends on `handle.waitForResolution()` while their `presentation`
view is shown, and the view calls `handle.complete()`.

## Installation

`LifecycleKit` is a local SPM library in this repo (`Shared/LifecycleKit`). Add
it to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourUI", dependencies: [.target(name: "LifecycleKit")])
```

## Core API

```swift
// Why we're launching — gates UI-bearing steps.
public enum LaunchReason { case userForeground, background(BackgroundCause) }
public struct LaunchModeSet: OptionSet { /* .foreground, .background, .all */ }

// One unit of launch work. Build with the Work/Interactive sugar and refine
// with chained modifiers.
public struct LaunchStep: Identifiable {
    public func when(_ predicate: @escaping @MainActor () async -> Bool) -> Self
    public func modes(_ modes: LaunchModeSet) -> Self
    public func presenting(_ view: ...) -> Self                 // always while running
    public func presenting(when: ..., _ view: ...) -> Self      // only if predicate holds at start
    public func presenting(after: Duration, _ view: ...) -> Self // only if still running after delay
}

@resultBuilder public enum LaunchBuilder {}                     // if / if-else / for
public struct LaunchSequence { public init(@LaunchBuilder _ steps: () -> [LaunchStep]) }

// Bridge between a running step and its presented view.
@MainActor @Observable public final class StepHandle {
    public let reason: LaunchReason
    public var progress: Double?      // determinate progress for the view
    public var message: String?
    public func complete()            // UI resumes the step
    public func fail(_ error: Error)  // UI fails the step
    public func waitForResolution() async throws
}

public enum LaunchPhase { case launching, running(LaunchStep, StepHandle), failed(LaunchFailure), ready }

@MainActor @Observable public final class Launcher {
    public private(set) var phase: LaunchPhase
    public init(reason: LaunchReason, prelude: @MainActor () -> Void = {}, sequence: LaunchSequence)
    public func run() async             // walk the steps; idempotent
    public func retry()                 // re-run from the failed step
    public func enterForeground() async // promote a background launch
    public func reset(_ sequence: LaunchSequence) async // reverse flow → relaunch
}
```

Plus free-function sugar so sequences read declaratively:

```swift
func Work(_ id: String, _ body: @escaping @MainActor (StepHandle) async throws -> Void) -> LaunchStep
func Interactive(_ id: String,
                 run: @escaping @MainActor (StepHandle) async throws -> Void = { try await $0.waitForResolution() },
                 @ViewBuilder presenting: @escaping @MainActor (StepHandle) -> some View) -> LaunchStep
```

`Interactive` defaults to `.modes(.foreground)`: a step whose whole job is to
wait for the user would deadlock during a headless background launch (there's no
UI to resolve it), so it's skipped there.

## Where the *final* app UI comes from

The launch sequence is only the **prerequisites**. The destination — the real,
"logged-in" / default app UI — is **not a step**; it's the `content` closure
handed to `LaunchContainer`, rendered when (and only when) the launcher reaches
`.ready`. (It can't be a step: steps complete and the cursor advances, whereas
the app UI is terminal and persists for the rest of the process lifetime.)

```swift
LaunchContainer(launcher) {       // `content` == the real app, the destination
    MainTabView()                 // appears once the launcher hits .ready
}
```

`LaunchContainer` renders from `launcher.phase`:

| phase | renders |
|-------|---------|
| `.launching` / a silent step | `splash()` (defaults to `LaunchSplash`) |
| `.running` with a presentation | that step's view (onboarding, migration) |
| `.failed` | `LaunchFailureView { launcher.retry() }` |
| `.ready` | `content()` — the destination UI |

For a **background launch** (`reason.isBackground`) it renders `EmptyView()`
always — even at `.ready` — so `content()` (the heavy view tree) is never built.

## Usage

Build the launcher early (e.g. in the app delegate, so a headless background
launch works before any window exists) and drive it:

```swift
// App delegate / launch site:
let launcher = Launcher(
    reason: launchOptions?[.location] != nil ? .background(.location) : .userForeground,
    prelude: { deps.installLocationManager() },   // synchronous, must-exist-now wiring
    sequence: LaunchSequence {
        Work("open-store") { _ in try await deps.openStore() }
            .presenting(when: { deps.migrationPredicted }) { MigrationProgressView(handle: $0) }

        Interactive("onboarding") { OnboardingView(handle: $0) }
            .when { !deps.hasOnboarded }

        Work("sync-auth")          { _ in await deps.syncAuthorization() }
        Work("reconcile-tracking") { _ in await deps.reconcileTracking() }
        Work("load")               { _ in await deps.refresh() }
    },
)
Task { await launcher.run() }
```

```swift
// Root view: gate the real app behind the launcher.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    let launcher: Launcher

    var body: some View {
        LaunchContainer(launcher) { MainTabView() }
            // run() is idempotent; promote a background launch only once the
            // scene is genuinely active, so a background-connected scene stays
            // headless.
            .task {
                await launcher.run()
                if scenePhase == .active { await launcher.enterForeground() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await launcher.enterForeground() }
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
        await launcher.reset(LaunchSequence {
            Work("erase")  { _ in try await deps.eraseAll() }
            Work("forget") { _ in deps.resetPreferences() }
        })
    }
}
```

If a teardown step throws, the launcher parks in `.failed` and does **not**
relaunch.

## Two correctness points designed in deliberately

- **Synchronous prelude vs. async steps.** The `prelude` runs synchronously at
  `init` for cheap, must-exist-now wiring (e.g. installing a `CLLocationManager`
  delegate a queued background event can't wait for). Everything expensive —
  including opening a store that may run a slow migration — belongs in an async
  step, so it never blocks `didFinishLaunching` (and the system watchdog).

- **Background launches build no UI.** iOS connects a background scene without
  displaying it and reclaims such apps first under memory pressure, so a
  background launch should build *no* view tree. `LaunchContainer` enforces this
  (`EmptyView()` for any background reason); the work still runs because it's
  driven from the launch site (`Task { await launcher.run() }`), independent of
  whether SwiftUI ever builds the hierarchy. When a window genuinely appears,
  `enterForeground()` promotes the launcher and re-drives so foreground-only
  steps (onboarding) now run.

All drives (`run` / `enterForeground` / `retry` / `reset`) are serialized
through a single internal task, so two never overlap (which would let, e.g., a
store-open step run twice concurrently).

## Testing

The engine and views are exercised with Swift Testing + a hosted UI test host.
What's worth covering when adopting it: step ordering, `.when` gating, mode
filtering (background skips foreground-only), thrown error → `.failed` +
`retry()` resuming from the failed step, interactive suspension until
`handle.complete()`, progress propagation, and `reset()` returning to
`.launching`. Because a real interactive step suspends, drive it from a `Task`
and poll `launcher.phase` until it parks, then resolve the handle.
