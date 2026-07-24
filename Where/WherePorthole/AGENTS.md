# WherePorthole – Module Shape

WherePorthole is the Where feature's Porthole connector: `WhereConnector` over
`WhereServices`, exposing residency data and a few safe actions. See
[`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md) — read those first.

## Scope & dependencies

- Depends on **PortholeKit** + **WhereCore** (RegionKit transitively). It reads
  *only* through `WhereServices` collaborators (`reports`, `evidence`,
  `resolution`, `ingestor`) — no new domain logic, no store I/O of its own.
- **Read-mostly, no destructive actions in v1.** `scan-data-issues`,
  `capture-location-now`, and `attribute-coordinate` are all safe. Backup export
  and store mutation are deliberately out (they need blob transfer / are
  destructive) — see the suite `TODOs.md`.

## Invariants

- **Preferences cross as a `Sendable` snapshot** (`WherePreferencesSnapshot`),
  not the non-Sendable `WherePreferences`, so handlers stay `@Sendable`.
- **Wired into the app through WhereUI, not the app target.** WhereUI (a dynamic
  framework) links this and every Porthole product; the `Where` app and
  `WhereUITests` add nothing, so no duplicate copy can split type-keyed metadata
  (root AGENTS.md "Targets"). The `DEBUG`-only `PortholeDeveloperView` in WhereUI
  builds the `Porthole` and registers the connectors.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`WherePortholeTests`, `extraPackageProducts: [PortholeKit, PortholeCore,
WhereCore, RegionKit]`). Build `WhereServices` over `SwiftDataStore.inMemory()` +
`IdleLocationSource` and seed via `journal`.
