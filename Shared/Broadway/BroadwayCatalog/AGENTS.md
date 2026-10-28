# BroadwayCatalog – Module Shape

BroadwayCatalog is the catalog **app**. It showcases BroadwayUI components. It depends on **BroadwayUI**. Entry point: `BroadwayApp.swift` (`@main`). See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../../AGENTS.md) and the group [`../AGENTS.md`](../AGENTS.md) first.

## Scope

- **Put app-specific views here, not in BroadwayUI.** Resources bundle through the `Resources/**` glob in [`Project.swift`](../../../Project.swift).
- **Declare a Tuist `.app` target** (`com.stuff.broadway.catalog`) for iPhone and iPad destinations.

## Testing

Run `BroadwayCatalogTests` (`./test BroadwayCatalogTests`). This app currently hosts its own tests. That deviates from the shared-`StuffTestHost` convention. Track it in [`../TODOs.md`](../TODOs.md).
