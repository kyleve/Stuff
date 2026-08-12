# TestHostSupport – Module Shape

TestHostSupport provides UIKit hosting and run-loop helpers (`show`, `hostKeyWindow`, `waitFor`) for hosted Swift Testing bundles in `StuffTestHost`. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../AGENTS.md) first. This file adds module rules.

## Scope & dependencies

- **Use UIKit, Foundation, and ObjectiveC only.** Use no sibling dependencies. ObjectiveC supports the associated-object window marker below.
- **Keep this module dependency-free.** Every test tree must link it without dragging in domain modules.
- **Declare the library target in [`Package.swift`](../../Package.swift).** Hosted test bundles consume it through the `unitTests` helper in [`Project.swift`](../../Project.swift) and through the `StuffTestHost` app.
- **Never link this module from a shipping app target.**

## Invariants an agent can't re-derive

- **The host stamps its window. Do not guess.** `hostKeyWindow()` returns only the window marked `isMainTestHostWindow`.
- **`StuffTestHost`'s `SceneDelegate` sets that marker.** Do not reintroduce a `first { $0.isKeyWindow } ?? first` search.
- **Key `isMainTestHostWindow` on a name-interned `Selector`.**
- **This module is statically embedded into the host app and each `.xctest` bundle.**
- **An associated-object key must resolve to the same pointer in every image.**
- **A per-image `static var key: UInt8` does not match across the host↔bundle boundary.**
- **That mismatch silently reads `nil`.** That flake is what this replaces.
- **`show` waits for readiness.** It pumps the run loop for the host window and root VC before hosting.
- **Then a test that runs before the scene connects does not fail spuriously.**
- **It follows Apple's parent/child VC order.** It always restores `layer.speed` through a `defer` at entry.

## Testing

No dedicated test bundle exists. Every hosted bundle that calls `show` exercises this module. Examples include `StuffTestHostSmokeTests`/`ShowLifecycleTests` in `LifecycleKitTests` and the `BroadwayUITests`/`WhereUITests` suites.
