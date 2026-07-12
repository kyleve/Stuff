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
- **The `BStylesheets` cache is shared across `BContext` copies.** `get(_:)` is
  non-mutating and writes newly-created sheets into the copy-on-write box in
  place (via `_unsafeUnderlyingValue`), so value copies of a context share one
  cache — a stylesheet is created once per `(type, traits, themes)` key and
  reused across copies and repeated access, until a trait/theme change swaps in
  a fresh cache. Don't assume reading `context.stylesheets` re-resolves. (See
  `BStylesheetCacheSharingTests`.)
- **`@_spi(CopyOnWrite)`** exposes the copy-on-write box internals
  (`_unsafeUnderlyingValue`) — used by that in-place cache write and by tests.

Tests: `BroadwayCoreTests` in `StuffTestHost` (`tuist test BroadwayCoreTests`).
