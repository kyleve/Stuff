# BroadwayTesting

UIKit test helpers for **hosted** Swift Testing bundles in the Broadway stack.
Tests run inside `StuffTestHost`, which provides a real key window; this module
places view controllers in that window and pumps the run loop until async UI
state settles.

BroadwayTesting is for test bundles only — do not link it from app targets.

## Public API

- `hostKeyWindow() -> UIWindow?` — the host's key window (or the first window in
  the first connected scene).
- `show(_:loadAndPlaceView:perform:)` — adds a view controller as a child of the
  host root VC, optionally places its view, runs the test closure, then tears
  down in UIKit container order. Speeds up animations (`layer.speed = 100`) for
  the duration (reset in `defer`).
- `waitFor(timeout:predicate:)` / `waitFor(timeout:block:)` — drive the run loop
  until a condition holds (throws on timeout).
- `waitForOneRunloop()`, `determineAverage(for:using:)`, and
  `UIView.recursiveDescription`.

## Install

Hosted Broadway test bundles get it via the `broadwayUnitTests` helper in
[`Project.swift`](../../../Project.swift), which also wires `StuffTestHost`.

## Testing

No dedicated test bundle; behavior is covered indirectly by `BroadwayCoreTests`
and `BroadwayUITests`.
