# BroadwayCore – Module Shape

Foundation of the Broadway stack: the `BContext` environment (traits, themes,
lazily-cached stylesheets) plus supporting value types (`AnyEquatable`,
`CopyOnWrite`, `TypeIdentifier`, `EquatableIgnored`). Foundation + UIKit; no app
or sibling-module imports. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope & invariants

- **Public API is `public`.** `BContext+UITraits.swift` bridges to
  `UITraitDefinition` under `#if canImport(UIKit)`.
- **`BContext` keeps its `BStylesheets` cache in sync.** Every `didSet` on
  `baseTraits` / `traitOverrides` / `themes` refreshes it; `stylesheets` is
  `@EquatableIgnored`, so it stays out of equality.
- **`@_spi(CopyOnWrite)`** exposes copy-on-write internals for tests only.

Tests: `BroadwayCoreTests` in `StuffTestHost` (`tuist test BroadwayCoreTests`).
