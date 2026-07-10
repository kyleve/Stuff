# BroadwayTesting – Module Shape

UIKit hosting + run-loop helpers (`show`, `hostKeyWindow`, `waitFor`,
`waitForOneRunloop`) for Broadway's hosted Swift Testing bundles. See
[`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope & invariants

- **Test-bundle-only** — never linked from app targets. UIKit + Foundation.
- **Runs inside the shared `StuffTestHost`.** `show` finds the host window via
  scene enumeration (`hostKeyWindow()`), matching `WhereTesting`; don't
  reintroduce a `UIApplication.shared.delegate?.window` lookup (the host is
  scene-based, so its window lives on the `UIWindowSceneDelegate`).
- **`show` follows UIKit container order** (`addChild` → attach → `didMove`,
  teardown reversed) and always restores `layer.speed` in `defer`.

## Testing

No dedicated test bundle; exercised via every hosted Broadway test that calls
`show` (`BroadwayCoreTests`, `BroadwayUITests`).
