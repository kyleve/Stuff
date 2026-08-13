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

- **SwiftUI + LifecycleKit + SFSafeSymbols only.** No app imports — app-specific launch UI
  (splashes, onboarding) lives in the consumer (e.g. `WhereUI`).
- The engine/UI split is deliberate: LifecycleKit must stay renderable-state
  only (no SwiftUI import); anything that builds a `View` belongs here.

## Invariants

- **`content` is only ever built from `.ready`'s carried value** — never
  re-read from shared state. It is built as soon as the value exists,
  *including under a splash hold* (the hold warms the destination). Keep it to
  **one** `content` call site — separate held/revealed branches give SwiftUI
  two identities and rebuild the destination at the reveal.
- **No view tree when `reason.buildsNoViewTree`** — even at `.ready`.
- **Every splash-showing state resolves to one `LaunchOverlay.splash` case** —
  never per-phase `switch` arms, which remount the splash at each boundary
  and reset its animations and caption timers.
- **A positive `minimumSplashDuration` covers the first visible ready reveal** —
  including an already-`.ready` mount when foreground promotion coalesced past
  the splash; `.zero` reveals immediately. Keep the positive-duration hold
  keyed on readiness *and* active-scene visibility, retain an observed splash's
  original deadline, and never arm or complete it offscreen. An interrupted
  first reveal returns to awaiting; only content whose uncovered frame was
  committed survives an ordinary resume without replay. Guards:
  `positiveMinimumCoversAlreadyReadyContent`,
  `positiveMinimumKeepsBackgroundReadyHeadless`,
  `promotedBackgroundReadyForcesTheFirstRevealSplash`,
  `interruptedFirstRevealWaitsAgainAfterTheSceneBecomesActive`. Assert
  "revealed" via the *absent splash*, not via `content` (content is built
  during a hold too); `isShowingSplash` must read the runner's own surface,
  never `displayedSurfaceIdentity`, which reports `.splash` for a held
  `.ready` and would re-arm the hold from its own release.
- **Gate views resolve only their own handle** — a superseded drive's handle
  no-ops; don't route gate resolution through anything else.
- **One registration per gate type** (construction `precondition`); a parked
  gate with no registration logs (`os`, subsystem `com.stuff.lifecyclekitui`)
  and fails the handle with `MissingGateViewError` onto the terminal failure
  surface — never an indefinite splash.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` via the
`LifecycleKitUITests` bundle: container tests host `LifecycleContainer` and
assert which branch renders (probe views), proxy tests cover the
connected/disconnected environment paths. Engine behavior is tested in
LifecycleKit's own bundle — don't duplicate it here.
