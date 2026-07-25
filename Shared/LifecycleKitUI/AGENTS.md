# LifecycleKitUI – Module Shape

The SwiftUI layer for [LifecycleKit](../LifecycleKit): `LifecycleContainer`
renders a `LifecycleRunner`'s `phase` (splash / gate view / failure / app
content), `GateView(for:content:)` registers gate views by gate *type*, and
`LifecycleProxy` (`@Environment(\.lifecycle)`) lets nested views reach
`enterForeground()`/`teardown(_:input:)`. The failure surface is terminal
(no retry). See [`README.md`](README.md) for the full
narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + LifecycleKit only.** No app imports — app-specific launch UI
  (splashes, onboarding) lives in the consumer (e.g. `WhereUI`).
- The engine/UI split is deliberate: LifecycleKit must stay renderable-state
  only (no SwiftUI import); anything that builds a `View` belongs here.

## Invariants

- **`content` is only ever built from `.ready`'s carried value** — never
  re-read from shared state. Don't add a code path that renders the app
  surface without the launch output in hand. It is built as soon as that value
  exists (from `phase.readyValue`), *including while a splash hold still covers
  it*, so the hold warms the destination instead of paying for its `.task`s and
  first layout in the frame the reveal starts. Keep it to **one** `content` call
  site: rendering it from separate held/revealed branches gives SwiftUI two
  identities and rebuilds the whole destination at the reveal, defeating that.
- **No view tree when `reason.buildsNoViewTree`** — even at `.ready`.
- **Every splash-showing state resolves to one `LaunchOverlay.splash` case,** so
  the splash keeps a single identity across `.launching` → each step → the hold.
  Don't render it from per-phase `switch` arms: SwiftUI would treat each arm's
  splash as a different view and remount it at every boundary, resetting the
  animations and caption timers a long-lived splash (e.g. Where's
  `LaunchSplashView`) documents as uninterrupted.
- **`minimumSplashDuration` only holds a splash that was actually shown.** The
  hold is armed when the splash *appears*, so a launch already `.ready` when the
  container mounts reveals immediately rather than stalling behind a minimum for
  a splash nobody saw (`minimumSplashDurationDoesNotHoldWhenNoSplashWasShown`
  guards this; the timing half is device-verified, not host-testable). Assert
  "revealed" via the *absent splash*, not via `content` — content is built
  during a hold too, so it no longer distinguishes the two. `isShowingSplash`
  must read the runner's own surface, never `displayedSurfaceIdentity` — that
  reports `.splash` for a held `.ready`, which would re-arm the hold from its own
  release and never reveal.
- **Gate views resolve only their own handle.** The registry hands each gate
  view the parked `LifecycleGateHandle`; a superseded drive's handle no-ops,
  so don't route gate resolution through anything but the handle.
- **One registration per gate type** (construction `precondition`); a parked
  gate with no registration is a programmer error — the container logs it
  (`os`, subsystem `com.stuff.lifecyclekitui`) and fails the gate's handle
  with `MissingGateViewError`, landing on the failure surface (visible and
  named (though terminal), identical in debug and release) rather than an indefinite
  splash.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` via the
`LifecycleKitUITests` bundle: container tests host `LifecycleContainer` and
assert which branch renders (probe views), proxy tests cover the
connected/disconnected environment paths. Engine behavior is tested in
LifecycleKit's own bundle — don't duplicate it here.
