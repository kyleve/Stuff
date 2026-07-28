# BroadwayCore

Foundation types for the Broadway design system. `BroadwayCore` defines the
`BContext` environment that flows through a view hierarchy, carrying the current
traits, themes, and a lazily-populated stylesheet cache.

## Public API

- **`BContext`** — root environment container (`baseTraits` + `traitOverrides`
  → `traits`, plus `themes` and a cached `BStylesheets`). `Equatable` +
  `Sendable`. `stylesheet(_:fallback:)` resolves a stylesheet inline (no `try`),
  trapping in debug and returning the fallback in release on a programmer error.
- **`BTraits` / `BThemes`** — type-keyed containers for trait and theme values;
  `BTraits.Overrides` layers scoped overrides over base traits.
- **`BStylesheets`** — lazy, cached stylesheet resolver scoped to traits+themes.
- **`BAccessibility`** — accessibility snapshot (`.current()`) + observation: a
  `UIViewController`-based `BTraitsValue` observer, plus a view-controller-free
  `.changes()` `AsyncStream` a SwiftUI root can consume from a `.task`.
- **Utilities** — `AnyEquatable` (type-erased `Equatable`), `CopyOnWrite`
  (`@_spi(CopyOnWrite)` copy-on-write wrapper), `EquatableIgnored`,
  `TypeIdentifier`, `StylesheetError`.

## How it works

`BContext` holds a `BStylesheets` cache that is rebuilt whenever `baseTraits`,
`traitOverrides`, or `themes` change (via `didSet`). The cache is
`@EquatableIgnored`, so two contexts compare equal on their inputs, not on the
derived cache. `BContext+UITraits.swift` bridges the context onto a
`UITraitCollection` custom trait (guarded by `#if canImport(UIKit)`).

## Install

Local SPM library declared in the root [`Package.swift`](../../../Package.swift):
depend on it with `.package(product: "BroadwayCore")`. Run tests with
`./test BroadwayCoreTests`.
