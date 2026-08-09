# LifecycleKitUI – Module Shape

LifecycleKitUI is the SwiftUI layer for [LifecycleKit](../LifecycleKit). `LifecycleContainer` renders a `LifecycleRunner`'s `phase` (splash, gate view, failure, app content). `GateView(for:content:)` registers gate views by gate *type*. `LifecycleProxy` (`@Environment(\.lifecycle)`) lets nested views reach `enterForeground()`/`teardown(_:input:)`. The failure surface is terminal (no retry). See [`README.md`](README.md) for the full narrative and API.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build system, formatting, and global conventions.

## Scope & dependencies

- **Use SwiftUI and LifecycleKit only.** Do not import app code. App-specific launch UI (splashes, onboarding) lives in the consumer (for example `WhereUI`).
- **Keep the engine/UI split deliberate.** LifecycleKit must stay renderable-state only (no SwiftUI import). Anything that builds a `View` belongs here.

## Invariants

- **Build `content` only from `.ready`'s carried value.** Never re-read from shared state. Build it as soon as the value exists, including under a splash hold (the hold warms the destination). Keep one `content` call site. Separate held/revealed branches give SwiftUI two identities and rebuild the destination at the reveal.
- **Build no view tree when `reason.buildsNoViewTree`.** That applies even at `.ready`.
- **Resolve every splash-showing state to one `LaunchOverlay.splash` case.** Never use per-phase `switch` arms. They remount the splash at each boundary and reset its animations and caption timers.
- **Hold `minimumSplashDuration` only for a splash that was actually shown.** Arm it when the splash appears, so an already-`.ready` mount reveals immediately. Guard: `minimumSplashDurationDoesNotHoldWhenNoSplashWasShown` (the timing half is device-verified, not host-testable). Assert "revealed" via the absent splash, not via `content` (content is built during a hold too). `isShowingSplash` must read the runner's own surface, never `displayedSurfaceIdentity`. That reports `.splash` for a held `.ready` and would re-arm the hold from its own release.
- **Resolve gate views only through their own handle.** A superseded drive's handle no-ops. Do not route gate resolution through anything else.
- **Allow one registration per gate type** (construction `precondition`). If a parked gate has no registration, log (`os`, subsystem `com.stuff.lifecyclekitui`) and fail the handle with `MissingGateViewError` onto the terminal failure surface. Never leave an indefinite splash.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` through the `LifecycleKitUITests` bundle. Container tests host `LifecycleContainer` and assert which branch renders (probe views). Proxy tests cover the connected/disconnected environment paths. Engine behavior is tested in LifecycleKit's own bundle. Do not duplicate it here.
