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
- Public API is `public`.

Tests: `BroadwayUITests` in `StuffTestHost`, linking `BroadwayTesting`
(`tuist test BroadwayUITests`).
