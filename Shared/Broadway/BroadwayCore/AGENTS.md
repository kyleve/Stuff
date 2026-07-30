# BroadwayCore – Module Shape

Foundation of the Broadway stack: the `BContext` environment (traits, themes,
lazily-cached stylesheets) plus supporting value types (`AnyEquatable`,
`CopyOnWrite`, `TypeIdentifier`, `EquatableIgnored`). Foundation + UIKit; no app
or sibling-module imports. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope & invariants

- **`BContext` keeps its `BStylesheets` lookup key in sync.** Every `didSet` on
  `baseTraits` / `traitOverrides` / `themes` calls `updateTraits` /
  `updateThemes`; `stylesheets` is `@EquatableIgnored`, so it stays out of
  equality.
- **The `BStylesheets` cache is shared across `BContext` copies.** `get(_:)` is
  non-mutating and writes newly-created sheets into the copy-on-write box in
  place (via `_unsafeUnderlyingValue`), so value copies of a context share one
  cache — a stylesheet is created once per `(type, traits, themes)` key and
  reused across copies and repeated access. A trait/theme change only moves the
  *key*: entries under the old key stay in the dictionary (nothing evicts them
  today — see the `TODO` in `BStylesheets.swift`) while lookups resolve fresh
  sheets under the new one. Don't assume reading `context.stylesheets`
  re-resolves. (See `BStylesheetCacheSharingTests`.)
- **`@_spi(CopyOnWrite)`** exposes the copy-on-write box internals
  (`_unsafeUnderlyingValue`) — used by that in-place cache write and by tests.

Tests: `BroadwayCoreTests` in `StuffTestHost` (`./test BroadwayCoreTests`).
