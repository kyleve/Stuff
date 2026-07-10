# BroadwayUI – Module Shape

UIKit + SwiftUI components that own and propagate a `BContext` down the view
hierarchy — `BRootViewController` (root container + trait observation) and
`BTraitOverridesViewController` (scoped overrides). Depends on **BroadwayCore**.
See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope & invariants

- **Shared components only** — app-specific views belong in BroadwayCatalog.
- **`BRootViewController` defers setup** until it enters a valid hierarchy
  (`viewIsAppearing`); `context` is `nil` before then, and the controller
  publishes the context to descendants through `traitOverrides.bContext`.
- Public API is `public`.

Tests: `BroadwayUITests` in `StuffTestHost`, linking `BroadwayTesting`
(`tuist test BroadwayUITests`).
