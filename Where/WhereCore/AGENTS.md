# WhereCore – Module Shape

WhereCore is the domain layer of the Where feature: the persistence boundary,
GPS ingestion, per-day / per-year aggregation, data-quality detection, and
the side effects that hang off a committed write. It is assembled behind one
`Sendable` value — `WhereServices` — that the UI and the App Intents stack
talk to (widgets never do; they read the published `WidgetSnapshot` from the
App Group). See [`README.md`](README.md) for the public API and collaborators.

The domain/presentation split and the rules WhereCore must uphold live in the
feature [`Where/AGENTS.md`](../AGENTS.md#layering) — read that and the root
[`AGENTS.md`](../../AGENTS.md) first. This file adds only the module's
internal shape.

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  must **not** import SwiftUI or UIKit — if a behavior would still be correct
  without SwiftUI, it belongs here, not in `WhereUI`.

## Shape & invariants

- **`WhereServices` is the composition root, not a god-object.** It wires
  focused single-responsibility collaborators (the live list is its
  initializer; `README.md` describes them) and owns the one
  cross-collaborator operation, `reset()`. Add new behavior to the
  collaborator it belongs to.
- **`WhereStore` is a value-type boundary.** Everything crossing it is a
  value, never a SwiftData record; every mutation runs inside
  `perform { … }` (the production store traps otherwise), stale-decision writes
  use `perform(expectedDataGenerationID:)`, and multi-table reads use `readSnapshot`;
  guard: `SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification`. Each
  committed transaction pings `changes()`. Never expose its `ModelContainer` through
  `WhereServices`; the separate DEBUG Inspector runtime uses
  `SwiftDataStore.makeContainer`, `inspectorModelTypes`, and
  `inspectorStoreURL` as its schema/storage adapter.
- **Resolve destructive generations as a multi-parent causal DAG.** A rotation names every real
  maximal head; two unjoined reset heads resolve to a deterministic empty UUIDv8 synthetic generation
  until the next rotation joins them, and persisted generation events must never use that reserved
  namespace. Retire a profile whose registration frontier omits any observed account-reset generation
  (`WhereDataGenerationTests.resetBarrierRejectsEarlierRegistrationAndAcceptsLaterRegistration`).
- **Each process opens its on-disk store once and injects it** — the app's
  launch opens it; the App Intents stack shares it via
  `WhereServices.forIntents(sharingStoreOf:)`. A second container over the
  same file is how a fresh install once raced the launch into failure (root
  [Composition](../../AGENTS.md#composition-create-once-inject-down)).
- **Primary regions *are* the tracked-region set.** `primaryRegions()` /
  `setPrimaryRegions(_:)` read/write the same `SDTrackedRegion` rows as
  `trackedRegions()` — picking scopes GPS attribution *and* carries each
  region's `RegionAppearance` + pick order. `RegionAppearance` carries the
  persisted `RegionSymbol`; its mapping to SFSafeSymbols and `Color` is
  presentation (WhereUI).
- **Export backups from one `readSnapshot` and keep restorable user data
  lossless.** Add persisted user-data shapes end-to-end and cover both import
  strategies, but export no target-owned recording check-ins and ignore any in
  an imported archive (`BackupServiceTests` / `BackupCoordinatorTests`).
- **Backup import never adopts or changes local recording consent.** Archives omit that
  device-local choice; Replace preserves it and every existing removal tombstone while rotating
  the data generation and discarding the local outbox (`BackupCoordinatorTests`).
- **Gate import recovery with a two-phase sidecar plus an atomic store receipt.** Never clear a
  committed onboarding marker before its independent terminal completion tombstone
  (`BackupCoordinatorTests` / `WhereLaunchTests`).
- **Keep the backup archive strict synthesized `Codable`.** A shape change bumps
  `BackupArchive.currentFormatVersion` and extends
  [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb); never add an
  in-code legacy decode fallback.
- **A logical day is a `CalendarDay`, not a `Date`.** `CalendarDay` (Y-M-D)
  is the timezone-independent identity every stored user record and day
  comparison keys on; persisting a `Date` makes a day drift across time-zone
  changes — the residency bug this exists to prevent. Use a `Date` only for
  genuine instants (GPS bucketing via `CalendarDay(from:in:)`, grid geometry,
  sorting, display), derived via `CalendarDay.startOfDay(in:)`.
  **Scope boundary:** only user-asserted records are travel-proof — a GPS
  sample is bucketed into a `CalendarDay` by the *current* calendar at read
  time, so a GPS-derived day (and a dismissed GPS-only issue keyed on it) can
  still shift by one across a time-zone change. Deliberate: "where was I on
  this *local* day?" — don't bucket GPS by a fixed home zone.
- **Composite identity keys are `store://` URLs, not joined strings.**
  Conform to `WhereStoreURLCodable` (see `DataIssueID`), building/parsing
  with `StoreURL`; families without a dedicated identity type get theirs from
  `WhereStoreID`. Used to stamp Periscope `LogEvent.externalID`s.
- **No in-app data migration or legacy recovery.** `SD….toValue()` reads only
  the current shape and fault-logs a row it can't place; incomplete generation or
  removal history throws and fails closed instead of dropping into a benign
  state. The one-time
  reshape path is backup **export → transform
  ([`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb)) →
  replace-import**. Deliberate pre-release; the durable successor
  (per-entity schema versioning) is filed in [`../TODOs.md`](../TODOs.md).
- **Writes await their side effects.** `DayJournal` commits, then awaits the
  reminder reconcile + widget publish in sequence, so a reader on the next
  `changes()` ping never observes a half-applied write.
- **Filter persistent-store remote-change notifications by the Where store URL
  and the store instance's transaction author.** Never let Periscope or Where's
  own local saves enter `remoteChanges()`; guard: `StoreRemoteChangeSourceTests`.
- **Post-write reconciliation is defined once.** Every write and import
  routes through `DayJournal.reconcileAfterDayDataChange()` (or its widget-less
  subset `reconcileIssueState()`) — never copy the fan-out into a new write
  path. Cross-collaborator hooks take a single closure wired at the
  composition root (`BackupCoordinator.ImportLifecycle.didCommit`).
- **Detectors read aggregated input; the speed-based one needs raw fixes.**
  `DataIssueInput.daySamples` carries per-day GPS fixes only (`.gpsVisit` /
  `.gpsSignificantChange`, sorted) — manual and evidence-implied samples are
  excluded so `FlightDayDetector`'s speed math isn't skewed.
- **Read related year projections from one samples snapshot.** Use
  `ReportReader.yearReportDetails(for:primaryRegionCount:)` for the scene's
  report and primary-region locations.
- **`LocationSource` abstracts GPS** — `CoreLocationSource` in production,
  `ScriptedLocationSource` in tests/previews; `requestCurrentLocation()`
  returns `nil`, never throws, and backs
  `LocationIngestor.captureTodayIfNeeded(now:)`.
- **`DeviceRecordingController` owns this installation's local recording choice and physical GPS
  state.** Serialize mutations across awaits, fail closed when the current identity is removed,
  stamp every ingested GPS sample with the current installation id, and apply
  `LocationHistoryReader` to every user-facing projection. Persist immutable profiles, nickname
  events, global removal tombstones, and target-owned advisory check-ins separately. A remote
  device may rename or remove an identity, but never change another installation's local consent.
  Backups alone read lossless raw
  samples and device/removal timelines, excluding non-restorable check-ins.
- **Journal complete `LocationOutbox` snapshots through `JournalKit`.** Stamp every entry with its
  authorizing data generation, never replay it into another generation, keep the directory excluded
  from device backups, and make a destructive clear durable before removing old segments; guards:
  `LocationOutboxTests` and `LocationIngestorTests.failedOutboxWriteStopsRecordingWithTheSampleStillInMemory`.
- **Tracked regions live in the store, not preferences** — one
  `SDTrackedRegion` row per region so cross-device edits merge; read as a
  `Set` defaulting to the four. `RegionAttribution` derives the attributor
  from them and rebuilds on `changes()`; assemble via the async
  `WhereServices.make(...)` / `forIntents()` so both attribute against the
  same synced set. `distanceToBoundary` is `nil` outside the tracked set.
- **Location-card history is non-authoritative preference state.** Keep its
  snapshots year-keyed by stable `Region` id, and clear them through
  `WherePreferences.reset()`; current report totals remain the source of truth.
- **`DemoDataBuilder` seeds through the ordinary write paths** (`DayJournal`,
  `setPrimaryRegions`) — no private door into the store, so a demo exercises
  the code a real user does. Its data is sized against the *elapsed* year, not
  the calendar; fixed sizes made a January demo mostly-unlogged. Guard:
  `DemoDataBuilderTests.holdsItsShapeWhereverInTheYearItIsEntered`.
- **Impossible states trap; recoverable ones surface.** `WhereStore` methods
  are `async throws`; a `catch` logs a typed `WhereLog` event (PII-free,
  `.public`, error as `LogAttachment.error(_:)`) and leaves state honest —
  never a benign-looking default. The `WhereLog` facade and every
  `*Log.swift` event type live together in `Sources/Logging/`.
- **Expensive Core work is spanned, with a budget** — bulk reads and `perform`
  commits, aggregation, calendar layout, issue detection, the reconcile
  fan-out, backup, GPS acquisition. Names come from each `*Log`'s nested
  `SpanName`; see [Spans](../AGENTS.md#spans) for the convention. A detector
  names its own span through `DataIssueDetecting.detects`, so
  `DataIssueScanner` reports per-category cost (`detect(border-drift)`) without
  a switch over concrete detector types.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in
`StuffTestHost`. Drive collaborators against `SwiftDataStore.inMemory()` +
`ScriptedLocationSource` — never the on-disk/CloudKit store or
`CoreLocationSource`. The CloudKit remote-import path uses the
`@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`.

`InMemoryKeyValueStore` and the noop schedulers/refreshers are plain `public`
production API, not test scaffolding: demo mode assembles a session out of
them. Don't restore the `@_spi(Testing)` + `#if DEBUG` gating the first two
once carried (#150).

The notification and widget seams run the other way round from most defaults
here: the `@_spi(Testing)` `init` defaults them to the **no-ops**, while the
public `make(...)` requires them. The reconcilers behind them fire on ordinary
writes, so a suite that named nothing would schedule real notifications and
reload the user's widget timelines as a side effect of saving a day. Only
`WhereBootstrap` names the real ones. `forIntents(sharingStoreOf:)` inherits
them from its base for the same reason it inherits the attributor — a stack
derived from the demo world must stay made of no-ops.
