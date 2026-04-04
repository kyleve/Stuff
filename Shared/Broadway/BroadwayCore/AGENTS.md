# BroadwayCore

Foundational utilities and shared logic. All other frameworks depend on this module.

## Key Types

- **BContext** — Root environment container with type-keyed themes, traits, and stylesheets.
- **BThemes** / **BTraits** — Type-keyed containers for theme and trait values.
- **BStylesheets** — Lazy cached stylesheet resolver.
- **BAccessibility** — Accessibility snapshot and observer.
- **AnyEquatable** — Type-erased Equatable wrapper.
- **CopyOnWrite** — COW property wrapper.
- **TypeIdentifier** — Lightweight type-keyed identifier.

## Conventions

- Mark all public API as `public`.
- `BContext+UITraits.swift` bridges to `UITraitDefinition` via `#if canImport(UIKit)`.
