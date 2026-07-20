# LifecycleKitUI

The SwiftUI layer for [LifecycleKit](../LifecycleKit): the container that
renders a `LifecycleRunner`'s observable `phase`, the gate-view registry, and
the environment proxy nested views use to reach the runner. The engine itself
(steps, plans, the runner) lives in LifecycleKit and knows nothing about
views; this module owns everything rendered.

## Quick start

```swift
import LifecycleKit
import LifecycleKitUI

LifecycleContainer(
    runner,                                   // LifecycleRunner<WhereSession>
    splash: { context in
        LaunchSplashView(caption: context?.message)
    },
    failure: { failure, retry in
        LifecycleFailureView(failure: failure, retry: retry)
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
| `.failed(failure)` | `failure(failure, retry)` |
| `.ready(value)` | `content(value)` |

- **`content` receives the launch's output.** `.ready` carries the trunk's
  final value, so the app surface cannot be built without the proof the
  launch produced — no optional re-reads from shared state.
- **Gate views are registered by gate type**, which statically recovers the
  gate's `Value`: the view gets `(LifecycleGateHandle, Value)` and resolves
  the handle (`complete()` / `fail(_:)`) to resume the trunk. A parked gate
  with no registration asserts in debug and falls back to the splash in
  release.
- **Headless launches render nothing.** When `reason.buildsNoViewTree` (a
  `.background` relaunch, or `.undetermined` before promotion) the container
  renders `EmptyView()` — even at `.ready` — so `content` is never built for
  a launch nobody sees.
- **Surface transitions animate on identity.** The phase's surface identity
  collapses `launching`/`running` into one splash surface, so a step
  advancing never re-triggers the transition; reaching a gate, `.failed`, or
  `.ready` animates with the caller-supplied `transition`/`animation`.
  Launch surfaces sit above `content` so a leaving splash plays its removal
  transition over the entering app.

## Reaching the runner from nested views

`LifecycleContainer` publishes a `LifecycleProxy` under
`@Environment(\.lifecycle)`. The proxy is non-generic (environment values
must be), forwards `retry()` / `enterForeground()` / `teardown(_:input:)`,
and is *disconnected* by default: calling through it without a container
above asserts in debug and no-ops in release.

```swift
@Environment(\.lifecycle) private var lifecycle
...
await lifecycle.teardown(WhereLaunch.resetPlan(for: model), input: session)
```

## Defaults

`LifecycleSplash` (a plain centered spinner) and `LifecycleFailureView` (a
`ContentUnavailableView` with a retry button) are used by the convenience
initializers when the host passes no custom surfaces.
