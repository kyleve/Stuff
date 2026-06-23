# WhereTesting – Module Shape

WhereTesting provides UIKit hosting and run-loop helpers for Swift Testing
bundles that run inside `StuffTestHost`. See [`README.md`](README.md) for the
public API and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the Where
feature [`AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **UIKit + Foundation** for helpers; **WhereCore** only for
  [`InMemoryKeyValueStore`](Sources/InMemoryKeyValueStore.swift).
- Library target in [`Package.swift`](../../Package.swift),
  `Where/WhereTesting/Sources`. Consumed by hosted test bundles via
  [`Project.swift`](../../Project.swift) `unitTests` helper — never by app
  targets.

## Key types & functions

- [`WhereTestingError`](Sources/WhereTesting.swift) — simple error wrapper for
  host/wait failures.
- [`hostKeyWindow()`](Sources/WhereTesting.swift) — key-window lookup shared by
  `show` and tests that assert host invariants.
- [`show(_:loadAndPlaceView:perform:)`](Sources/WhereTesting.swift) — container
  VC lifecycle: `addChild` → attach view → `didMove(toParent:)`; teardown in
  reverse. Animation speed reset lives in a top-level `defer`.
- [`waitFor`](Sources/WhereTesting.swift) / [`waitForOneRunloop`](Sources/WhereTesting.swift)
  / [`renders(within:_:)`](Sources/WhereTesting.swift) — main-run-loop polling.
- [`InMemoryKeyValueStore`](Sources/InMemoryKeyValueStore.swift) — in-memory
  `KeyValueStore` with plist round-trip fidelity.

## Invariants to preserve

- **UIKit container contract in `show`.** Child lifecycle order must match Apple's
  parent/child VC guidance; tests rely on real `viewWillAppear` / `viewDidAppear`.
- **`layer.speed` always restored.** The speed override uses `defer` at function
  entry so a trapping test body cannot leave the host window animating at 100×.
- **Main-actor isolation.** All public entry points are `@MainActor`; hosted tests
  should use `@MainActor` test types or `@MainActor` test functions.

## Conventions

- Follow the root rules: exhaustive `switch`, no closure `Binding(get:set:)` in
  any future SwiftUI helpers.
- Keep helpers test-only and side-effect free outside the host window hierarchy.
- English error strings are fine (test module).

## Testing

No self-test bundle yet (`WhereTestingTests` is needs-design). Coverage today:

- [`ShowLifecycleTests`](../../Shared/LifecycleKit/Tests/ShowLifecycleTests.swift)
  — appearance lifecycle and SwiftUI `onAppear`.
- Hosted UI tests across `WhereUITests`, `LogViewerUITests`, etc.

When adding a dedicated test bundle, cover store plist round-trip traps, `show`
without root VC, and `waitFor` timeout without blocking on the WhereCore split.
