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
  surface without the launch output in hand.
- **No view tree when `reason.buildsNoViewTree`** — even at `.ready`.
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
