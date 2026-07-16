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
- **A logical day is a `CalendarDay`, not a `Date`.** `CalendarDay` (year-month-
  day) is the timezone-independent identity of a day, and it is what every
  *stored user record* and *day comparison* keys on: `DayPresence.day`,
  `SDManualDay.dayKey`, `RegionDayLocations.day`, `MissingDayRange`, the
  missing-day / detector present-sets, and `DataIssueID` (hence persisted
  dismissals — a `DataIssueID` is identified by its `store://issues/…` URL over
  `CalendarDay`s). A `Date` is an absolute instant, so persisting a day as
  one makes it drift onto a *different* day when the device changes time zones —
  the residency bug this exists to prevent. Reach for a `Date` only where you
  genuinely need an instant — bucketing a GPS `sample.timestamp` into a day
  (`CalendarDay(from:in:)` with the working calendar), calendar-grid geometry,
  sorting, or display — and derive it via `CalendarDay.startOfDay(in:)` /
  `DayPresence.startOfDay(in:)`; never store an instant as the key.
  **Scope boundary:** this pins *stored user records* (manual days,
  dismissals) to a fixed day, but a GPS `sample.timestamp` is still bucketed into
  a `CalendarDay` by the *current* calendar at read time, so a GPS-derived day
  can still shift by one across a time-zone change — and with it a dismissed
  *GPS-only* border-drift / abrupt-change issue (whose id is that re-bucketed
  day) can reappear. Only user-asserted records and their keys are
  travel-proof; travel-proofing GPS-derived detections would mean bucketing GPS
  by a fixed home zone, which we intentionally don't do ("where was I on this
  *local* day?").
- **Composite identity keys are `store://` URLs, not joined strings.** A value
  whose identity is composite persists and round-trips as a single `store://`
  URL via `WhereStoreURLCodable` (see `DataIssueID`), which hands the conformer
  `Codable` and a stable SwiftData string key for free — never an ad-hoc
  `type:value` string or a hand-written keyed `Codable`. Build/parse with
  `StoreURL` so every conformer shares the `store://<collection>/<type>?<params>`
  shape.
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
  reminder reconcile + widget publish in sequence, so a reader on the next
  `changes()` ping never observes a half-applied write. `DataIssueScanner` drops
  its cache on the same signal *and* is invalidated inline where a caller needs
  it provably fresh (see `WhereServices.reset()`), which is the deterministic
  half of that pair, not redundant with it.
- **Post-write reconciliation is defined once.** Every write and import routes
  through `DayJournal.reconcileAfterDayChange()` (or its widget-less subset
  `reconcileIssueState()` for dismiss/restore paths) — never copy the reconcile
  fan-out into a new write path. Cross-collaborator hooks take a single closure
  wired at the composition root (`BackupCoordinator.onImport`), not an injected
  list of reconcilers.
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
  async `WhereServices.make(...)` (which reads the set) so the app and the App
  Intents process (`WhereServices.forIntents()`, also async) attribute against
  the same synced set. Detection is naturally scoped to it — the attributor only
  loads tracked-region geometry, so `distanceToBoundary` is `nil` elsewhere.
- **Impossible states trap; recoverable ones surface.** `WhereStore` methods are
  `async throws` so the CloudKit-backed store can report I/O failure; a `catch`
  must log via `WhereLog.channel(_:)` (typed `Category`, PII-free) and leave
  state honest — never swallow into an empty default.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in `StuffTestHost`.
Drive collaborators against `SwiftDataStore.inMemory()` + `ScriptedLocationSource`
— never the on-disk/CloudKit store or `CoreLocationSource`. The CloudKit
remote-import path uses the `@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`. `InMemoryKeyValueStore` (the `KeyValueStore` test
double) ships here behind `@_spi(Testing)` + `#if DEBUG` — not in a test-only
module — so it never ships in release; test bundles get it with
`@_spi(Testing) import WhereCore`.
