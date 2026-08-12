# LifecycleKitUI

The SwiftUI layer for [LifecycleKit](../LifecycleKit).
It provides the container that renders a `LifecycleRunner`'s observable `phase`, the gate-view registry, and the environment proxy nested views use to reach the runner.
The engine itself (steps, plans, the runner) lives in LifecycleKit and knows nothing about views.
This module owns everything rendered.

## Quick start

```swift
import LifecycleKit
import LifecycleKitUI

LifecycleContainer(
    runner,                                   // LifecycleRunner<WhereSession>
    splash: { context in
        // The running step's context is handed in so a splash can show a
        // caption/progress; Where's own splash ignores it and self-manages.
        MySplashView(status: context?.message)
    },
    failure: { failure in
        LifecycleFailureView(failure: failure)   // terminal — no retry
    },
    gates: {
        GateView(for: OnboardingGate.self) { handle, session in
            OnboardingView(gate: handle, session: session)
        }
    },
) { session in
    MainTabs(session: session)                // non-optional: .ready carries it
}
```

## What renders when

| Runner phase | Surface |
|---------------------|-------------------------------------------------|
| `.launching` | `splash(nil)` |
| `.running(context)` | `splash(context)` — caption/progress off the context |
| `.awaitingGate(handle)` | the `GateView` registered for the gate's *type* |
| `.failed(failure)` | `failure(failure)` — terminal, no retry |
| `.ready(value)` | `content(value)` |

- **`content` receives the launch's output.** `.ready` carries the trunk's final value, so the app surface cannot be built without the proof the launch produced — no optional re-reads from shared state.
- **Gate views are registered by gate type**, which statically recovers the gate's `Value`.
  The view gets `(LifecycleGateHandle, Value)` and resolves the handle (`complete()` / `fail(_:)`) to resume the trunk.
  A parked gate with no registration is logged and failed with `MissingGateViewError`, so the launch lands on the (terminal) failure surface — visible and named — instead of an indefinite splash.
  Debug and release behave identically.
- **Headless launches render nothing.** When `reason.buildsNoViewTree` (a `.background` relaunch, or `.undetermined` before promotion) the container renders `EmptyView()` — even at `.ready` — so `content` is never built for a launch nobody sees.
- **Surface transitions animate on identity.** The phase's surface identity collapses `launching`/`running` into one splash surface, so a step advancing never re-triggers the transition.
  Reaching a gate, `.failed`, or `.ready` animates with the caller-supplied `transition`/`animation`.
  Launch surfaces sit above `content` so a leaving splash plays its removal transition over the entering app.

## Holding the splash on a fast launch

A fast launch can finish before the splash is ever seen (an optimized build may reach `.ready` in a few frames), so its reveal flashes past.
Pass `minimumSplashDuration` to hold the splash up for at least that long once it first appears, then play the reveal.
It defaults to `.zero` (reveal as soon as the runner is ready).
The hold is per-appearance, so a reset relaunch (or the return from a gate) gets its own minimum:

```swift
LifecycleContainer(runner, minimumSplashDuration: .seconds(1)) { session in
    MainTabs(session: session)
}
```

While the hold is in effect the container keeps reporting the *splash* surface identity, so the reveal transition fires when the hold releases rather than the instant the runner reports `.ready`.

The hold is not dead time.
`content` is built as soon as the launch produces its value — beneath the splash that is still covering it — so the destination's `.task`s and first layout happen *during* the hold instead of in the frame the reveal animation starts.
It stays gated on the launch's output either way (that value is only readable from `.ready`), so nothing is built speculatively.
The hold stops being a stall and starts being a warm-up.

## Reaching the runner from nested views

`LifecycleContainer` publishes a `LifecycleProxy` under `@Environment(\.lifecycle)`.
The proxy is non-generic (environment values must be), forwards `enterForeground()` / `teardown(_:input:)`, and is *disconnected* by default.
Calling through it without a container above asserts in debug and no-ops in release.

```swift
@Environment(\.lifecycle) private var lifecycle
...
await lifecycle.teardown(WhereLaunch.resetPlan(for: model), input: session)
```

## Defaults

`LifecycleSplash` (a plain centered spinner) and `LifecycleFailureView` (a terminal `ContentUnavailableView`, no retry button) are used by the convenience initializers when the host passes no custom surfaces.
