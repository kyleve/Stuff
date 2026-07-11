# BroadwayUI – Module Shape

UIKit + SwiftUI components that own and propagate a `BContext` down the view
hierarchy — `BRootViewController` (UIKit root container + trait observation),
`BRootView` / `.broadwayRoot(themes:)` (the SwiftUI-native root), and
`BTraitOverridesViewController` (scoped overrides). Depends on **BroadwayCore**.
See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope & invariants

- **Shared components only** — app-specific views belong in BroadwayCatalog.
- **`BRootViewController` defers setup** until it enters a valid hierarchy
  (`viewIsAppearing`); `context` is `nil` before then, and the controller
  publishes the context to descendants through `traitOverrides.bContext`.
- **`BRootView` has no `BTraitsObserver`** — SwiftUI re-evaluates `body` on
  color-scheme / Dynamic Type changes, and a `.task` mirrors
  `BAccessibility.changes()` into state; both rebuild the injected `BContext`.
  Context-building lives in `BRootContext.make(...)` so the trait mapping is
  testable without a host.
- **`\.bContext` prefers a synchronous SwiftUI value.** `BContext+SwiftUI` reads
  a pure-SwiftUI `EnvironmentKey` (set by `BRootView` / `broadwayRoot` /
  `bTraitOverrides`) and only falls back to the UIKit trait-bridged value when
  none is set — so SwiftUI-side context propagates without a `UITraitCollection`
  round-trip (no first-frame lag). A SwiftUI-set context is *not* written back
  to UIKit traits, so it doesn't reach nested UIKit views; seed
  `BRootViewController` when the context must reach UIKit descendants.
- Public API is `public`.

Tests: `BroadwayUITests` in `StuffTestHost`, linking `BroadwayTesting`
(`tuist test BroadwayUITests`).
