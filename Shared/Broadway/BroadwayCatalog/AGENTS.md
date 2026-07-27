# BroadwayCatalog – Module Shape

The catalog **app** — a showcase of BroadwayUI components. Depends on
**BroadwayUI**. Entry point `BroadwayApp.swift` (`@main`). See
[`README.md`](README.md).

Complements the root [`AGENTS.md`](../../../AGENTS.md) and the group
[`../AGENTS.md`](../AGENTS.md). Read those first.

## Scope

- App-specific views live here, not in BroadwayUI. Resources bundle via the
  `Resources/**` glob in [`Project.swift`](../../../Project.swift).
- Declared as a Tuist `.app` target (`com.stuff.broadway.catalog`),
  iPhone/iPad destinations.

Tests: `BroadwayCatalogTests`, hosted by this app itself — not `StuffTestHost`
(`tuist test BroadwayCatalogTests`).
