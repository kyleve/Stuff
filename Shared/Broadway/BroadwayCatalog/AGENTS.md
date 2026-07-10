# BroadwayCatalog

The catalog app — a living showcase of BroadwayUI components. Depends on BroadwayUI.

## Structure

- `Sources/` — App views and logic. Entry point is `BroadwayApp.swift` (`@main`).
- `Resources/` — Asset catalogs, localization files, and other bundled resources.

## Conventions

- App-specific views go here, not in BroadwayUI.
- Resources are bundled via the `Resources/**` glob in `Project.swift`.
