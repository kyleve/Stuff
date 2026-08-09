# BroadwayCore – Module Shape

BroadwayCore is the foundation of the Broadway stack. It provides the `BContext` environment (traits, themes, lazily-cached stylesheets) and supporting value types (`AnyEquatable`, `CopyOnWrite`, `TypeIdentifier`, `EquatableIgnored`). It uses Foundation and UIKit. It imports no app or sibling modules. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../../AGENTS.md) and the group [`../AGENTS.md`](../AGENTS.md) first.

## Scope & invariants

- **Keep the `BStylesheets` lookup key in sync on `BContext`.** Every `didSet` on `baseTraits`, `traitOverrides`, or `themes` must call `updateTraits` or `updateThemes`. `stylesheets` is `@EquatableIgnored`, so it stays out of equality.
- **Share the `BStylesheets` cache across `BContext` copies.** `get(_:)` is non-mutating. It writes newly-created sheets into the copy-on-write box in place through `_unsafeUnderlyingValue`. Value copies of a context share one cache. A stylesheet is created once per `(type, traits, themes)` key. A trait or theme change only moves the key. Entries under the old key stay in the dictionary. Nothing evicts them today. See the `TODO` in `BStylesheets.swift`. Lookups resolve fresh sheets under the new key. Do not assume reading `context.stylesheets` re-resolves. See `BStylesheetCacheSharingTests`.
- **Expose copy-on-write box internals through `@_spi(CopyOnWrite)`.** `_unsafeUnderlyingValue` supports that in-place cache write and tests.

## Testing

Run `BroadwayCoreTests` in `StuffTestHost` (`./test BroadwayCoreTests`).
