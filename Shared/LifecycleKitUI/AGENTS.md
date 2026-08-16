# LifecycleKitUI – Module Shape

LifecycleKitUI is the SwiftUI layer for [LifecycleKit](../LifecycleKit). `LifecycleContainer` renders a `LifecycleRunner`'s `phase` (splash, gate view, failure, app content). `GateView(for:content:)` registers gate views by gate *type*. `LifecycleProxy` (`@Environment(\.lifecycle)`) lets nested views reach `enterForeground()`/`teardown(_:input:)`. The failure surface is terminal (no retry). See [`README.md`](README.md) for the full narrative and API.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build system, formatting, and global conventions.

## Scope & dependencies

- **Use SwiftUI, LifecycleKit, and SFSafeSymbols only.** Do not import app code. App-specific launch UI (splashes, onboarding) lives in the consumer (for example `WhereUI`).
- **Keep the engine/UI split deliberate.** LifecycleKit must stay renderable-state only (no SwiftUI import). Anything that builds a `View` belongs here.

## Invariants

- **Build `content` only from `.ready`'s carried value.** Never re-read from shared state.
- **Build content as soon as the value exists, including under a splash hold.** The hold warms the destination.
- **Keep one `content` call site.** Separate held/revealed branches give SwiftUI two identities and rebuild the destination at the reveal.
- **Build no view tree when `reason.buildsNoViewTree`.** That applies even at `.ready`.
- **Resolve every splash-showing state to one `LaunchOverlay.splash` case.** Never use per-phase `switch` arms. They remount the splash at each boundary and reset its animations and caption timers.
- **A positive `minimumSplashDuration` covers the first visible ready reveal.** That includes an already-`.ready` mount when foreground promotion coalesced past the splash. `.zero` reveals immediately.
- **Key the positive-duration hold on readiness and active-scene visibility.** Retain an observed splash's original deadline. Never arm or complete the hold offscreen.
- **An interrupted first reveal returns to awaiting.** Only content whose uncovered frame was committed survives an ordinary resume without replay.
- **Guards:** `positiveMinimumCoversAlreadyReadyContent`, `positiveMinimumKeepsBackgroundReadyHeadless`, `promotedBackgroundReadyForcesTheFirstRevealSplash`, `interruptedFirstRevealWaitsAgainAfterTheSceneBecomesActive`.
- **Assert "revealed" via the absent splash, not via `content`.** Content is built during a hold too.
- **`isShowingSplash` must read the runner's own surface, never `displayedSurfaceIdentity`.** That reports `.splash` for a held `.ready` and would re-arm the hold from its own release.
- **Resolve gate views only through their own handle.** A superseded drive's handle no-ops. Do not route gate resolution through anything else.
- **Allow one registration per gate type** (construction `precondition`).
- **If a parked gate has no registration, log** (`os`, subsystem `com.stuff.lifecyclekitui`) **and fail the handle with `MissingGateViewError` onto the terminal failure surface.** Never leave an indefinite splash.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` through the `LifecycleKitUITests` bundle. Container tests host `LifecycleContainer` and assert which branch renders (probe views). Proxy tests cover the connected/disconnected environment paths. Engine behavior is tested in LifecycleKit's own bundle. Do not duplicate it here.
