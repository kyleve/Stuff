# BroadwayCatalog

A showcase app for BroadwayUI components.
It is the living catalog for the Broadway design system.

## Structure

- `Sources/` — app views and entry point (`BroadwayApp.swift`, `@main`).
- `Resources/` — bundled resources (asset catalogs, etc.).

## Build & run

`BroadwayCatalog` is a Tuist `.app` target (`com.stuff.broadway.catalog`, iPhone/iPad).
It is declared in [`Project.swift`](../../../Project.swift).
Regenerate the project with `./ide --no-open`.
Then build or run the `BroadwayCatalog` scheme.
Run tests with `./test BroadwayCatalogTests`.
