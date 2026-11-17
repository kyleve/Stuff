# WhereCore — Domain contracts

Read the [feature contract](../AGENTS.md) and [repository contract](../../AGENTS.md).
The [README](README.md) owns the API and collaborator overview.

## Required task guidance

Read matching contracts before changing or reviewing the behavior, including tests and callers outside the owning directory.

| Task | Required guidance |
| --- | --- |
| Logical days, calendar bucketing, or day-key persistence | [Days](Sources/Days/AGENTS.md) |
| Backups, import recovery, or archive formats | [Backups](Sources/Backup/AGENTS.md) |
| Planned stays, forecasting, Home, or planning backup validation | [Forecasting](Sources/Forecasting/AGENTS.md) |
| Recording consent, device identities, or historical names | [Recording devices](Sources/Devices/AGENTS.md) |
| GPS acquisition, ingestion, or durable outbox behavior | [Location](Sources/Location/AGENTS.md) |
| Preference persistence, reset, themes, diagnostics, or presentation state | [Preferences](Sources/Preferences/AGENTS.md) |
| GPS reviews, sample corrections, or scan publication | [Data resolution](Sources/DataResolution/AGENTS.md) |

## Shape & invariants

- Keep compatibility metadata outside SwiftData. Inject one process-owned coordinator before every production store open.
  Only local recording On with Always permission can advance the shared version. Never lower a server or receipt version.
  Require an explicit transport and receipt store in every environment. Local operation uses the same verification path.
  Keep the receipt atomic, domain-bound, App Group-specific, and excluded from backups. A confirmed absent account can use local storage; unavailable/restricted accounts cannot. Preserve the version floor across domain changes and verify cloud evidence before enabling sync.
  Guards: `DataCompatibilityCoordinatorTests`, `DataCompatibilityReceiptTests`, `DataModelVersionTests`.
- Retire ingestion before joining recording operations. A retired scope must never restart GPS, including after an import completes.
  Preserve consent and the durable location outbox. Guards: `LocationIngestorTests`, `DeviceRecordingControllerTests`.

- Do not import SwiftUI or UIKit. Widgets read published App Group data and presentation files; they never construct `WhereServices`.
- Keep behavior on the owning collaborator. `WhereServices` assembles collaborators and owns their shared `reset()`.
- On-disk storage requires an explicit App Group identifier selected by the host. Keep production/development defaults out of Core.
- Use InstallerKit for build identity, feed validation, and cache policy. Keep `WherePreferences.installerUpdates` device-local; expose an installer identity from `BuildInfo` only for Development.
- Families without a dedicated identity type use `WhereStoreID`. Follow the Swift wire-format convention for composite keys.

### Persistence and generations

- Stale-decision writes use `perform(expectedDataGenerationID:)`; multi-table reads use `readSnapshot`.
  A snapshot within a mutation pins durable history through its pre-save check. Concurrent commits must throw `WhereStoreReadConflictError` before local edits save.
  Guard: `SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification`.
- Never expose `ModelContainer` through `WhereServices`. The separate DEBUG Inspector runtime uses the store's schema/storage adapter.
- Resolve destructive generations as a multi-parent causal DAG. A rotation names every real maximal head.
  Unjoined reset heads resolve to a deterministic empty UUIDv8 synthetic generation until a rotation joins them; persisted events cannot use that reserved namespace.
  Retire profiles whose registration frontier omits an observed account reset.
  Guard: `WhereDataGenerationTests.resetBarrierRejectsEarlierRegistrationAndAcceptsLaterRegistration`.
- No in-app data migration or legacy recovery. Current-shape decoding fault-logs unplaceable rows; incomplete generation/removal history throws and fails closed.
  The pre-release reshape path is backup export → [external transform](../Tools/upgrade-backup.rb) → replace-import.
- Observe remote history through Where's container and exclude this store instance's transaction author.
  Neither Periscope saves nor Where's own local saves enter `remoteChanges()`. Guard: `StoreRemoteChangeSourceTests`.

### Writes and projections

- `DayJournal` writes commit, then await reminder reconciliation and widget publication in sequence before returning.
  Route new writes through `reconcileAfterDayDataChange()` or `reconcileIssueState()`; the `setPrimaryRegions` and summary fan-out paths remain incomplete ([backlog](https://linear.app/kve/view/1cdf347a9c54)).
- User-facing location reads use `LocationHistoryReader.projection`: removal cutoffs precede correction revisions.
  Reports, maps, artwork, widgets, summaries, reminders, and intents use effective attribution. Trajectory assessment and review retain raw observations.
  Pin live attribution and its tracked set in the same snapshot.
- Read related year projections from one samples snapshot through `ReportReader.yearReportDetails(for:)`.
- Elsewhere is read-only. Preserve explicit corrections and manual assertions; never write inferred catalog names into reports, calendars, or widget totals.
  Load full-catalog geometry only on demand.
- Primary regions and tracked regions are the same store rows, including appearance and pick order. Keep them out of preferences so cross-device edits merge.
  App and intent assembly must attribute against the same synced set; boundary distance is unavailable outside that set.
  Symbol/color mapping belongs to WhereUI.
- Seed demos through ordinary write paths. Size data against the elapsed year; configured issue categories remain independently selectable.
  Keep early-year clock adjustments inside the in-memory demo.
  Guard: `DemoDataBuilderTests.holdsItsShapeWhereverInTheYearItIsEntered`.

### Manual entries

`DayJournal` manual-entry writes require an explicit `audit:` argument with no default.
An additive backfill must not downgrade an authoritative row's regions. The newer audit wins.

## Testing

For Core tests, fixtures, factories, or demo/no-op collaborator visibility, read the [test contracts](Tests/AGENTS.md).
