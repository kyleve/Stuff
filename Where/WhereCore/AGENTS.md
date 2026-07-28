# WhereCore – Module Shape

WhereCore is the domain layer of the Where feature: the persistence boundary,
GPS ingestion, per-day / per-year aggregation, data-quality detection, and the
side effects that hang off a committed write (reminders, widgets, backup,
on-device activity summaries). It is assembled behind one `Sendable` value —
`WhereServices` — that the UI and widgets talk to. See [`README.md`](README.md)
for the public API and how the pieces fit.

The **domain/presentation split and the rules WhereCore must uphold** (the
`WhereServices` entry point, `WhereStore.perform` writes, the single
read-refresh signal, `WhereLog` logging, `LocationSource`, `ManualEntryAudit`)
live in the feature [`Where/AGENTS.md`](../AGENTS.md#layering) — read that and
the root [`AGENTS.md`](../../AGENTS.md) first. This file adds only the module's
internal shape.

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  must **not** import SwiftUI or UIKit — if a behavior would still be correct
  without SwiftUI, it belongs here, not in `WhereUI`.

## Shape & invariants

- **`WhereServices` is the composition root**, not a god-object. It wires the
  focused, single-responsibility collaborators (`ReportReader` reads,
  `DayJournal` writes, `LocationIngestor` GPS, `DataIssueScanner` detection, the
  reminder / summary / issue-alert reconcilers, `WidgetSnapshotPublisher`,
  `BackupCoordinator`, `RecentActivitySummarizer`) and owns the one
  cross-collaborator operation, `reset()`. Add new behavior to the collaborator
  it belongs to.
- **`WhereStore` is a value-type boundary.** Everything crossing it is a value,
  never a SwiftData record; every mutation runs inside `perform { … }` (the
  production `SwiftDataStore` traps otherwise), and each committed transaction
  pings `changes()` — the single signal readers refresh from. The live
  `ModelContainer` is surfaced only for the read-only debug inspector.
  Each process opens its on-disk store **once** and injects it — the app's
  launch opens it, and the App Intents stack shares it via
  `WhereServices.forIntents(sharingStoreOf:)` — rather than a second caller
  opening another container over the same file (concurrent first-launch
  creation is how the launch once failed).
- **Primary regions *are* the tracked-region set.** The picked primary regions
  (`primaryRegions()` / `setPrimaryRegions(_:)`) are the same `SDTrackedRegion`
  rows `trackedRegions()` reads — picking scopes GPS attribution *and* carries
  each region's `RegionAppearance` (color token / emoji / SF Symbol) + pick
  order. `RegionAppearance` is data (WhereCore); the token→`Color` mapping and
  option catalogs are presentation (`WhereUI`).
- **Backups mirror the persisted model — keep them lossless.** Any change to
  persisted data (a new/changed `SD*` field, or a value type that crosses
  `WhereStore`) must be reflected end-to-end in the backup so export/restore
  never silently drops it: add it to `BackupArchive`, write it in
  `BackupService.makeArchiveFile`, read it back in `BackupCoordinator.importBackup`
  for **both** `.replace` and `.merge`, and add a round-trip test
  (`BackupServiceTests` for the archive, `BackupCoordinatorTests` for the store
  round-trip). The archive is **strict synthesized `Codable`** — no in-code
  legacy decode. A shape change **bumps `BackupArchive.currentFormatVersion`**
  (`readArchive` rejects any other version) and is handled out of band by
  extending [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb), per the
  no-migration-on-read rule below. Example: v2 added `primaryRegions` (per-region
  picked appearance + pick order), the tool synthesizes it from the legacy
  `trackedRegions` ids, and import restores looks from it.
- **A logical day is a `CalendarDay`, not a `Date`.** Every stored user record
  and day comparison keys on `CalendarDay` (year-month-day), because a `Date` is
  an absolute instant and persisting a day as one makes it drift onto a
  *different* day when the device changes time zones — the residency bug this
  exists to prevent. Reach for a `Date` only where you genuinely need an instant
  (bucketing a GPS `sample.timestamp`, grid geometry, sorting, display) and
  derive it via `CalendarDay.startOfDay(in:)`. `TimeZoneIndependenceTests` is
  the guard, and its doc comment carries the original bug report.
  - **Scope boundary an agent would get wrong:** only *user-asserted* records
    are travel-proof. A GPS `sample.timestamp` is bucketed by the *current*
    calendar at read time, so a GPS-derived day can still shift by one across a
    time-zone change — and with it a dismissed GPS-only border-drift or
    abrupt-change issue, whose id is that re-bucketed day, can reappear. Fixing
    that would mean bucketing GPS by a fixed home zone, which we deliberately
    don't do: the question is "where was I on this *local* day?".
- **Composite identity keys are `store://` URLs, not joined strings.** Conform to
  `WhereStoreURLCodable` (see `DataIssueID`) and build/parse with `StoreURL`; it
  hands you `Codable` and a stable SwiftData string key for free, so never an
  ad-hoc `type:value` string or a hand-written keyed `Codable`. Families with no
  dedicated identity type (days, years, evidence, samples) get theirs from
  `WhereStoreID`. `WhereStoreURLCodableTests` pins the shape, the round-trip, and
  the rejection of malformed URLs.
- **No in-app data migration or legacy recovery.** A data-shape change is not
  migrated on read or at boot: `SD….toValue()` reads only the current shape and
  drops (fault-logs) a row it can't place — e.g. an `SDManualDay` with no
  `dayKey`. The one-time path to reshape existing data is a backup **export →
  transform → replace-import**, where the transform is
  [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb) (rekeys regions,
  fills defaults, rewrites dismissal keys to `store://` URLs, resets the format
  version). This is deliberate for pre-release; the durable, general successor
  (per-entity schema versioning) is tracked in [`../TODOs.md`](../TODOs.md).
- **Writes await their side effects.** `DayJournal` commits, then awaits the
  reminder reconcile and widget publish in sequence, so a reader on the next
  `changes()` ping never sees a half-applied write
  (`DayJournalTests.addManualDayReconcilesAndPublishes`). `DataIssueScanner`
  drops its cache on the same signal *and* is invalidated inline where a caller
  needs it provably fresh (`WhereServices.reset()`) — the deterministic half of
  that pair, not redundant with it.
- **Detectors read aggregated input; the speed-based one needs raw fixes.**
  `DataIssueScanner` builds `DataIssueInput` from the `YearReport` plus
  `daySamples` — per-day GPS fixes (`.gpsVisit` / `.gpsSignificantChange` only,
  sorted by timestamp), the one field that keeps per-fix timestamps. Manual and
  evidence-implied samples are excluded so `FlightDayDetector`'s speed math
  isn't skewed by user-asserted timestamps.
- **Post-write reconciliation is defined once.** A write or import reconciles by
  calling `DayJournal.reconcileAfterDayChange()` (or its widget-less subset
  `reconcileIssueState()` for dismiss/restore paths) — never by copying the
  fan-out into a new write path. Cross-collaborator hooks take a single closure
  wired at the composition root (`BackupCoordinator.onImport`), not an injected
  list of reconcilers. **Two known paths don't yet honor this**, so don't read
  it as "reconciliation has already happened" when working nearby:
  `WhereServices.setPrimaryRegions(_:)` commits and pings `changes()` without
  the fan-out, and the daily summary reconciles only on launch/foreground
  `configure` and settings edits. Both are tracked in
  [`../TODOs.md`](../TODOs.md); a new write path should route through the fan-out
  rather than copy their omission.
- **`LocationSource` abstracts GPS.** Production is `CoreLocationSource` (Visits
  + significant-change); tests/previews use `ScriptedLocationSource`. The
  one-shot `requestCurrentLocation()` returns `nil` (never throws) when no fix
  is available — it stamps a manual entry's audit trail and backs
  `LocationIngestor.captureTodayIfNeeded(now:)`, which persists a fix for today
  (via the normal ingest path) when the app opens on a day with no GPS sample.
- **Tracked regions live in the store, not preferences.** They're synced app
  data (one `SDTrackedRegion` row per region so concurrent cross-device edits
  merge; read as a `Set`, defaulting to the four when unset). `RegionAttribution`
  derives the attributor from them and rebuilds on `changes()`; assemble via the
  async `WhereServices.make(...)`, which reads the set. The App Intents stack
  does **not** re-read it: `WhereServices.forIntents(sharingStoreOf:)` is
  synchronous and non-throwing precisely because it reuses the assembled
  layer's store, attributor, aggregator, and clock, swapping in only an
  `IdleLocationSource` — so the two can't drift apart, and installing the stack
  has no failure path. (`makeForIntents(store:now:)` is the async test seam
  that derives attribution from a seeded store instead.) Detection is naturally
  scoped to the set — the attributor only loads tracked-region geometry, so
  `distanceToBoundary` is `nil` elsewhere.
- **Adding an external package means re-running `./attribution`.** WhereCore
  links the app's only third-party package (ZIPFoundation), but it does **not**
  own attribution: the report format and tooling are
  [`CreditKit`](../../Shared/CreditKit/AGENTS.md)'s, and the report itself is the
  app target's resource. Regenerate and commit it, or the app ships a library
  whose license it doesn't reproduce.
- **`AppAttribution` and `BuildInfo` both read *this bundle*, and both treat
  absence as legitimate.** Only the app target gets a stamped Info.plist and a
  generated report, so a bundle without either (RegionViewer, `StuffTestHost`,
  an extension) reports `nil` rather than a placeholder. `AppAttribution` splits
  that from a report that is present and won't decode, which is a corrupt
  resource and faults — don't collapse the two back together. See [Version and
  build metadata](../../AGENTS.md#version-and-build-metadata) and
  [Attribution](../../AGENTS.md#attribution).
- **Read the app's report through `AppAttribution.main`, not
  `current(bundle: .main)`.** The report inlines every notice, so decoding it is
  not free, and its caller is a SwiftUI default argument — which Swift
  re-evaluates on every `init`, and SwiftUI re-inits views constantly. `main`
  caches the decode for the process; `current(bundle:)` stays for tests and for
  any bundle that isn't `.main`.
- **Impossible states trap; recoverable ones surface.** `WhereStore` methods are
  `async throws` so the CloudKit-backed store can report I/O failure; a `catch`
  must log via a `WhereLog` typed `LogEvent` (PII-free, `.public`) and leave
  state honest — never swallow into an empty default. This module owns the
  `WhereLog` facade every Where module logs through; see the feature
  [`AGENTS.md`](../AGENTS.md#layering) for the logging rules themselves.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in `StuffTestHost`.
Drive collaborators against `SwiftDataStore.inMemory()` + `ScriptedLocationSource`
— never the on-disk/CloudKit store or `CoreLocationSource`. The CloudKit
remote-import path uses the `@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`.

**The no-op collaborators are production API, not test scaffolding.**
`InMemoryKeyValueStore` and the noop schedulers/refreshers
(`NoopLoggingReminderScheduler`, `NoopDailySummaryScheduler`,
`NoopDataIssueAlertScheduler`, `NoopWidgetTimelineRefresher`,
`NoOpLocationOutbox`) are plain `public` and ship in release, because the app's
**demo mode** assembles a whole session out of them — in-memory preferences and
schedulers that never ask for a system permission. Tests and previews use them
too, but that's no longer what keeps them here, so don't "restore" the
`@_spi(Testing)` + `#if DEBUG` gating the first two used to carry. Genuine
test-only hooks (failure injection, queue introspection, clock overrides) still
follow the root convention.
