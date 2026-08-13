# TestHostSupport – Module Shape

UIKit hosting + run-loop helpers (`show`, `hostKeyWindow`, `waitFor`) for the
hosted Swift Testing bundles that run inside `StuffTestHost` — the single,
dependency-free home for them. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- **UIKit + Foundation + ObjectiveC only, no sibling deps** (ObjectiveC for
  the associated-object window marker below). Keeping it dependency-free is
  the point: every test tree links it without dragging in any domain module.
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
- **Both `show` overloads wait for readiness.** They pump the run loop for the
  host window + root VC before hosting, follow Apple's parent/child VC order,
  and always restore `layer.speed` via a `defer` at entry.

## Testing

No dedicated test bundle; exercised by every hosted bundle that calls `show`
(`StuffTestHostSmokeTests`/`ShowLifecycleTests` in `LifecycleKitTests`, the
`BroadwayUITests`/`WhereUITests` suites, …).
