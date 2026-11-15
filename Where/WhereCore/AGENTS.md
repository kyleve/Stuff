# WhereCore – Module Shape

WhereCore is the domain layer of the Where feature. It owns the persistence
boundary, GPS ingestion, per-day / per-year aggregation, data-quality
detection, and the side effects that hang off a committed write. It is
assembled behind one `Sendable` value — `WhereServices`. The UI and the App
Intents stack talk to it. Widgets never do. They read the published data and
presentation files from the App Group. See [`README.md`](README.md) for the
public API and collaborators.

The domain/presentation split and the rules WhereCore must uphold live in the
feature [`Where/AGENTS.md`](../AGENTS.md#layering). Read that and the root
[`AGENTS.md`](../../AGENTS.md) first. This file adds only the module's
internal shape.


## Required task guidance

Read the matching instructions before changing or reviewing that behavior, including its tests and callers outside this directory.

| Task | Required guidance |
| --- | --- |
| Logical days, calendar bucketing, or day-key persistence | [Day contracts](Sources/Days/AGENTS.md) |
| Backups, import recovery, or archive formats | [Backup contracts](Sources/Backup/AGENTS.md) |
| Planned stays, forecasting, Home, or planning backup validation | [Forecasting contracts](Sources/Forecasting/AGENTS.md) |
| Recording consent, device identities, or historical names | [Recording-device contracts](Sources/Devices/AGENTS.md) |
| GPS acquisition, ingestion, or durable outbox behavior | [Location acquisition and outbox contracts](Sources/Location/AGENTS.md) |
| Preference persistence, reset, themes, diagnostics, or presentation state | [Preference contracts](Sources/Preferences/AGENTS.md) |

## Shape & invariants

- Do not import SwiftUI or UIKit into WhereCore.
- Use InstallerKit for local and published build identity, feed validation, and cache policy.
  Keep `WherePreferences.installerUpdates` device-local. `BuildInfo` exposes an
  installer identity only for the Development audience.

- **`WhereServices` is the composition root, not a god-object.** It wires
  focused single-responsibility collaborators (the live list is its
  initializer. `README.md` describes them). It owns the one
  cross-collaborator operation, `reset()`. Add new behavior to the
  collaborator it belongs to.
- **`WhereStore` extends the feature's mutation boundary.** Stale-decision writes use `perform(expectedDataGenerationID:)`. Multi-table reads use
  `readSnapshot`. Guard:
  `SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification`. A snapshot
  inside a mutation pins durable history until its pre-save check; concurrent
  commits throw `WhereStoreReadConflictError` before local edits are saved. Each
  committed transaction pings `changes()`. Never expose its `ModelContainer`
  through `WhereServices`. The separate DEBUG Inspector runtime uses
  `SwiftDataStore.makeContainer`, `inspectorModelTypes`, and
  `inspectorStoreURL` as its schema/storage adapter.
- **Resolve destructive generations as a multi-parent causal DAG.** A rotation
  names every real maximal head. Two unjoined reset heads resolve to a
  deterministic empty UUIDv8 synthetic generation until the next rotation joins
  them. Persisted generation events must never use that reserved namespace.
  Retire a profile whose registration frontier omits any observed account-reset
  generation
  (`WhereDataGenerationTests.resetBarrierRejectsEarlierRegistrationAndAcceptsLaterRegistration`).
- **On-disk storage always carries an explicit App Group identifier.** Audience
  selection belongs to host targets; WhereCore must not own a production or
  development default.
- **Primary regions *are* the tracked-region set.** `primaryRegions()` /
  `setPrimaryRegions(_:)` read/write the same `SDTrackedRegion` rows as
  `trackedRegions()`. Picking scopes GPS attribution *and* carries each
  region's `RegionAppearance` + pick order. `RegionAppearance` carries the
  persisted `RegionSymbol`. Its mapping to SFSafeSymbols and `Color` is
  presentation (WhereUI).
- Families without a dedicated identity type use `WhereStoreID`. The Swift wire-format convention owns composite-key encoding.
- **No in-app data migration or legacy recovery.** `SD….toValue()` reads only
  the current shape and fault-logs a row it cannot place. Incomplete generation
  or removal history throws and fails closed instead of dropping into a benign
  state. The one-time reshape path is backup **export → transform
  ([`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb)) →
  replace-import**. Deliberate pre-release. The durable successor
  (per-entity schema versioning) is filed in [Where backlog](https://linear.app/kve/view/1cdf347a9c54).
- **Writes await their side effects.** `DayJournal` commits. Then it awaits
  the reminder reconcile + widget publish in sequence. A reader on the next
  `changes()` ping never observes a half-applied write.
- **Observe remote history through Where's `ModelContainer` and exclude this
  store instance's transaction author.** Never let Periscope or Where's own
  local saves enter `remoteChanges()`. Guard: `StoreRemoteChangeSourceTests`.
- **Route new writes through the existing reconciliation seams.** Use
  `DayJournal.reconcileAfterDayDataChange()` or `reconcileIssueState()`.
  Do not copy the incomplete `setPrimaryRegions` or summary fan-out paths
  tracked in [Where backlog](https://linear.app/kve/view/1cdf347a9c54).
- Follow the scoped [data-resolution rules](Sources/DataResolution/AGENTS.md)
  for GPS reviews, sample corrections, and scan publication.
- **Use `LocationHistoryReader.projection` for every user-facing location read.**
  Apply removal cutoffs before correction revisions. Reports, maps, artwork,
  widgets, summaries, reminders, and intents use effective attribution; trajectory
  assessment and review retain raw observations. Pin live attribution to the
  tracked set in the same store snapshot.
- **Read related year projections from one samples snapshot.** Use
  `ReportReader.yearReportDetails(for:)` for the scene's report, configured
  primary set, primary-region locations, and Elsewhere evidence.
- **Elsewhere is a read-only projection.** `ElsewhereResolver` expands ordinary
  Other coordinates against the catalog on its actor. Preserve explicit sample
  corrections and manual assertions. Never write inferred names back to reports,
  calendars, or widget totals. Load full-catalog geometry only on demand.
- **Tracked regions live in the store, not preferences.** One
  `SDTrackedRegion` row per region so cross-device edits merge. Read as a
  `Set` defaulting to the four. `RegionAttribution` derives the attributor
  from them and rebuilds on `changes()`. Assemble via the async
  `WhereServices.make(...)` / `forIntents()` so both attribute against the
  same synced set. `distanceToBoundary` is `nil` outside the tracked set.
- **`DemoDataBuilder` seeds through the ordinary write paths** (`DayJournal`,
  `setPrimaryRegions`). No private door into the store. A demo exercises
  the code a real user does. Its data is sized against the *elapsed* year, not
  the calendar. Configured issue categories must be independently selectable:
  checked categories appear and unchecked categories do not. Keep any
  early-year clock adjustment inside the in-memory demo. Guard:
  `DemoDataBuilderTests.holdsItsShapeWhereverInTheYearItIsEntered`.
- When an event accepts `LogError`, pass the original error through `.restricted(.errorDetails, error)` without a duplicate error attachment.
  PeriscopeCore owns the structured-error contract; the Swift conventions own failure propagation.
- **Expensive Core work is spanned, with a budget.** That includes bulk reads
  and `perform` commits, aggregation, calendar layout, issue detection, the
  reconcile fan-out, backup, GPS acquisition. Names come from each `*Log`'s
  nested `SpanName`. See [Spans](../Guidance/logging.md#spans) for the convention. A
  detector names its own span through `DataIssueDetecting.detects`.
  `DataIssueScanner` measures detector passes with `detect(category)` and the
  shared flight/boundary assessment with `assessGPS`; see `DataIssueScannerLog`.

## Testing

For Core tests, fixtures, test factories, or demo/no-op collaborator visibility, read the [test contracts](Tests/AGENTS.md).
