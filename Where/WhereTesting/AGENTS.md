# WhereTesting – Module Shape

WhereTesting provides UIKit hosting and run-loop helpers (`show(_:perform:)`,
`waitFor`, `renders(within:_:)`, `InMemoryKeyValueStore`) for Swift Testing
bundles that run inside `StuffTestHost`. See [`README.md`](README.md) for the
public API and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **UIKit + Foundation**, plus **WhereCore** only for `InMemoryKeyValueStore`.
- Library target in [`Package.swift`](../../Package.swift), consumed by hosted
  test bundles via the `Project.swift` `unitTests` helper — never by app
  targets. Keep helpers test-only and side-effect free outside the host
  window hierarchy.

## Invariants

- **`show` follows Apple's parent/child VC contract** (`addChild` → attach →
  `didMove(toParent:)`, teardown in reverse) — tests rely on real
  `viewWillAppear`/`viewDidAppear`.
- **`layer.speed` is always restored** via a `defer` at function entry, so a
  trapping test body can't leave the host window animating at 100×.
- All public entry points are `@MainActor`.

## Testing

No self-test bundle yet; coverage comes from `ShowLifecycleTests` (in
`LifecycleKitTests`) and every hosted UI test that uses `show`.
