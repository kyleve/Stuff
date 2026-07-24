# WherePorthole

WherePorthole is the Where feature's [Porthole](../../Shared/Porthole) connector:
read-mostly access to residency data through the existing `WhereServices`
collaborators, plus a couple of safe actions. It adds no domain logic and no
destructive actions.

## Using it

```swift
import WherePorthole

porthole.register(WhereConnector(
    services: services,
    preferences: WherePreferencesSnapshot(/* … from WherePreferences … */),
))
```

`WherePreferences` isn't `Sendable`, so the connector takes a `Sendable`
snapshot of the preference values it exposes and uses the drift threshold for
scans.

## Surface (id `where`)

- Data source `year-report` (filter `year`) — per-region day counts.
- Data source `manual-days` (filter `year`) — user-asserted day entries.
- Data source `evidence` (filter `year`) — evidence metadata (no blob bytes).
- Data source `preferences` — a single-row preferences snapshot.
- Data source `data-issues` (filter `year`) — data-quality issue counts by
  category (cached scan).
- Action `scan-data-issues` (`year`) — force a fresh scan; returns counts.
- Action `capture-location-now` — one-shot GPS fix, or null.
- Action `attribute-coordinate` (`latitude`, `longitude`) — the region a point
  falls in.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`WherePortholeTests`). Builds `WhereServices` over `SwiftDataStore.inMemory()` +
`IdleLocationSource`, seeds a manual day, and asserts the year-report/manual-days
/preferences/data-issues rows and the three actions (including an
`attribute-coordinate` spot-check for California).
