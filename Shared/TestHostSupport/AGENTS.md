# TestHostSupport – Module Shape

UIKit hosting + run-loop helpers (`show`, `hostKeyWindow`, `waitFor`)
for the hosted Swift Testing bundles that run inside
`StuffTestHost`. The single, dependency-free home for helpers that were
previously duplicated across `WhereTesting` and `BroadwayTesting`. See
[`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- **UIKit + Foundation only, no sibling deps.** Keeping it dependency-free is the
  whole point: both the Where and Broadway test trees link it without dragging in
  the Where domain (which is why the old `broadwayUnitTests` split existed — it's
  gone now that both use this module).
- Library target in [`Package.swift`](../../Package.swift); consumed by hosted
  test bundles via the `unitTests` helper in [`Project.swift`](../../Project.swift)
  and by the `StuffTestHost` app. **Never linked from a shipping app target.**

## Invariants an agent can't re-derive

- **The host stamps its window; we don't guess.** `hostKeyWindow()` returns only
  the window marked `isMainTestHostWindow` (set by `StuffTestHost`'s
  `SceneDelegate`) — never "the first key window". Don't reintroduce a
  `first { $0.isKeyWindow } ?? first` search.
- **`isMainTestHostWindow` is keyed on a name-interned `Selector`.** This module
  is statically embedded into the host app *and* each `.xctest` bundle, so an
  associated-object key must resolve to the same pointer in every image. A
  per-image `static var key: UInt8` would not match across the host↔bundle
  boundary and would silently read `nil` — the exact flake this replaces.
- **`show` waits for readiness.** It pumps the run loop for the host window + root
  VC before hosting, so a test running before the scene connects doesn't fail
  spuriously; it follows Apple's parent/child VC order and always restores
  `layer.speed` via a `defer` at entry.

## Testing

No dedicated test bundle; exercised by every hosted bundle that calls `show`
(`StuffTestHostSmokeTests`/`ShowLifecycleTests` in `LifecycleKitTests`, the
`BroadwayUITests`/`WhereUITests` suites, …).
