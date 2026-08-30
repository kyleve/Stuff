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

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  must **not** import SwiftUI or UIKit. If a behavior would still be correct
  without SwiftUI, it belongs here, not in `WhereUI`.

## Shape & invariants

- **`WhereServices` is the composition root, not a god-object.** It wires
  focused single-responsibility collaborators (the live list is its
  initializer. `README.md` describes them). It owns the one
  cross-collaborator operation, `reset()`. Add new behavior to the
  collaborator it belongs to.
- **`WhereStore` is a value-type boundary.** Everything crossing it is a
  value, never a SwiftData record. Every mutation runs inside
  `perform { … }` (the production store traps otherwise). Stale-decision
  writes use `perform(expectedDataGenerationID:)`. Multi-table reads use
  `readSnapshot`. Guard:
  `SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification`. Each
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
- **Each process opens its on-disk store once and injects it.** The app's
  launch opens it. The App Intents stack shares it via
  `WhereServices.forIntents(sharingStoreOf:)`. A second container over the
  same file is how a fresh install once raced the launch into failure (root
  [Composition](../../AGENTS.md#composition-create-once-inject-down)).
- **Primary regions *are* the tracked-region set.** `primaryRegions()` /
  `setPrimaryRegions(_:)` read/write the same `SDTrackedRegion` rows as
  `trackedRegions()`. Picking scopes GPS attribution *and* carries each
  region's `RegionAppearance` + pick order. `RegionAppearance` carries the
  persisted `RegionSymbol`. Its mapping to SFSafeSymbols and `Color` is
  presentation (WhereUI).
- **Export backups from one `readSnapshot` and keep restorable user data
  lossless.** Add persisted user-data shapes end-to-end and cover both import
  strategies. Export no target-owned recording check-ins. Ignore any in an
  imported archive (`BackupServiceTests` / `BackupCoordinatorTests`).
- **Backup import never adopts or changes local recording consent.** Archives
  omit that device-local choice. Replace preserves it and every existing
  removal tombstone while rotating the data generation and discarding the local
  outbox (`BackupCoordinatorTests`).
- **Gate import recovery with a two-phase sidecar plus an atomic store
  receipt.** Never clear a committed onboarding marker before its independent
  terminal completion tombstone
  (`BackupCoordinatorTests` / `WhereLaunchTests`).
- **Keep the backup archive strict synthesized `Codable`.** A shape change
  bumps `BackupArchive.currentFormatVersion` and extends
  [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb). Never add an
  in-code legacy decode fallback.
- **The planned stay is a generation-scoped last-writer register with tombstones.** Resolve
  duplicate CloudKit revisions by `updatedAt` then UUID, and clear or expire by writing a newer
  `nil` value; deleting the winner can resurrect stale intent (`PlannedStayCoordinatorTests`).
- **Keep planned-stay location checks advisory.** `PlannedStayLocationVerifier` accepts a fix
  inside the region or within the configured drift threshold outside its boundary. Do not add
  horizontal accuracy to the threshold.
- **A logical day is a `CalendarDay`, not a `Date`.** `CalendarDay` (Y-M-D)
  is the timezone-independent identity every stored user record and day
  comparison keys on. Persisting a `Date` makes a day drift across time-zone
  changes. That is the residency bug this exists to prevent. Use a `Date` only
  for genuine instants (GPS bucketing via `CalendarDay(from:in:)`, grid
  geometry, sorting, display). Derive via `CalendarDay.startOfDay(in:)`.
  **Scope boundary:** only user-asserted records are travel-proof. A GPS
  sample is bucketed into a `CalendarDay` by the *current* calendar at read
  time. A GPS-derived day (and a dismissed GPS-only issue keyed on it) can
  still shift by one across a time-zone change. Deliberate: "where was I on
  this *local* day?" Do not bucket GPS by a fixed home zone.
- **Composite identity keys are `store://` URLs, not joined strings.**
  Conform to `WhereStoreURLCodable` (see `DataIssueID`). Build and parse
  with `StoreURL`. Families without a dedicated identity type get theirs from
  `WhereStoreID`. Used to stamp Periscope `LogEvent.externalID`s.
- **No in-app data migration or legacy recovery.** `SD….toValue()` reads only
  the current shape and fault-logs a row it cannot place. Incomplete generation
  or removal history throws and fails closed instead of dropping into a benign
  state. The one-time reshape path is backup **export → transform
  ([`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb)) →
  replace-import**. Deliberate pre-release. The durable successor
  (per-entity schema versioning) is filed in [`../TODOs.md`](../TODOs.md).
- **Writes await their side effects.** `DayJournal` commits. Then it awaits
  the reminder reconcile + widget publish in sequence. A reader on the next
  `changes()` ping never observes a half-applied write.
- **Filter persistent-store remote-change notifications by the Where store URL
  and the store instance's transaction author.** Never let Periscope or Where's
  own local saves enter `remoteChanges()`. Guard: `StoreRemoteChangeSourceTests`.
- **Post-write reconciliation is defined once.** Every write and import
  routes through `DayJournal.reconcileAfterDayDataChange()` (or its widget-less
  subset `reconcileIssueState()`). Never copy the fan-out into a new write
  path. Cross-collaborator hooks take a single closure wired at the
  composition root (`BackupCoordinator.ImportLifecycle.didCommit`).
- **Detectors read aggregated input. The speed-based one needs raw fixes.**
  `DataIssueInput.daySamples` carries per-day GPS fixes only (`.gpsVisit` /
  `.gpsSignificantChange`, sorted). Manual and evidence-implied samples are
  excluded so `FlightDayDetector`'s speed math is not skewed.
- **Read related year projections from one samples snapshot.** Use
  `ReportReader.yearReportDetails(for:primaryRegionCount:)` for the scene's
  report and primary-region locations.
- **`LocationSource` abstracts GPS.** `CoreLocationSource` runs in production.
  `ScriptedLocationSource` runs in tests/previews. `requestCurrentLocation()`
  returns `nil`, never throws. It backs
  `LocationIngestor.captureTodayIfNeeded(now:)`.
- **`DeviceRecordingController` owns this installation's local recording choice
  and physical GPS state.** Serialize mutations across awaits. Fail closed when
  the current identity is removed. Stamp every ingested GPS sample with the
  current installation id. Apply `LocationHistoryReader` to every user-facing
  projection. Persist immutable profiles, nickname events, global removal
  tombstones, and target-owned advisory check-ins separately. A remote device
  may rename or remove an identity. It must never change another installation's
  local consent. Backups alone read lossless raw samples and device/removal
  timelines, excluding non-restorable check-ins.
- **Journal complete `LocationOutbox` snapshots through `JournalKit`.** Stamp
  every entry with its authorizing data generation. Never replay it into
  another generation. Keep the directory excluded from device backups. Make a
  destructive clear durable before removing old segments. Guards:
  `LocationOutboxTests` and
  `LocationIngestorTests.failedOutboxWriteStopsRecordingWithTheSampleStillInMemory`.
- **Tracked regions live in the store, not preferences.** One
  `SDTrackedRegion` row per region so cross-device edits merge. Read as a
  `Set` defaulting to the four. `RegionAttribution` derives the attributor
  from them and rebuilds on `changes()`. Assemble via the async
  `WhereServices.make(...)` / `forIntents()` so both attribute against the
  same synced set. `distanceToBoundary` is `nil` outside the tracked set.
- **Location-card history is non-authoritative preference state.** Keep its
  snapshots year-keyed by stable `Region` id. Clear them through
  `WherePreferences.reset()`. Current report totals remain the source of truth.
- **Keep diagnostic reporting intent in one encoded composite preference.** Keep crash,
  replay, remote threshold, and metadata policy vendor-neutral. Invalid stored
  values assert in Debug and resolve remote logging Off. Reset removes every reporting key.
- **`WhereTheme` is device-local preference state, not backup/domain data.**
  Preserve its stable raw values. Make unknown or missing values Standard. Publish it through
  `WidgetPresentationPublisher`. Never put it in `WidgetSnapshot`. Never rebuild widget data for a
  presentation-only change.
- **`DemoDataBuilder` seeds through the ordinary write paths** (`DayJournal`,
  `setPrimaryRegions`). No private door into the store. A demo exercises
  the code a real user does. Its data is sized against the *elapsed* year, not
  the calendar. Configured issue categories must be independently selectable:
  checked categories appear and unchecked categories do not. Guard:
  `DemoDataBuilderTests.holdsItsShapeWhereverInTheYearItIsEntered`.
- **Impossible states trap. Recoverable ones surface.** `WhereStore` methods
  are `async throws`. A `catch` logs a typed `WhereLog` event (PII-free,
  `.public`, error as `LogAttachment.error(_:)`) and leaves state honest.
  Never use a benign-looking default. The `WhereLog` facade and every
  `*Log.swift` event type live together in `Sources/Logging/`.
- **Expensive Core work is spanned, with a budget.** That includes bulk reads
  and `perform` commits, aggregation, calendar layout, issue detection, the
  reconcile fan-out, backup, GPS acquisition. Names come from each `*Log`'s
  nested `SpanName`. See [Spans](../AGENTS.md#spans) for the convention. A
  detector names its own span through `DataIssueDetecting.detects`. Then
  `DataIssueScanner` reports per-category cost (`detect(border-drift)`) without
  a switch over concrete detector types.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in
`StuffTestHost`. Drive collaborators against `SwiftDataStore.inMemory()` +
`ScriptedLocationSource`. Never use the on-disk/CloudKit store or
`CoreLocationSource`. The CloudKit remote-import path uses the
`@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`.

`InMemoryKeyValueStore` and the noop schedulers/refreshers are plain `public`
production API, not test scaffolding. Demo mode assembles a session out of
them. Do not restore the `@_spi(Testing)` + `#if DEBUG` gating the first two
once carried (#150).

The notification and widget seams run the other way round from most defaults
here. The `@_spi(Testing)` `init` defaults them to the **no-ops**. The
public `make(...)` requires them. The reconcilers behind them fire on ordinary
writes. A suite that named nothing would schedule real notifications and
reload the user's widget timelines as a side effect of saving a day. Only
`WhereBootstrap` names the real ones. `forIntents(sharingStoreOf:)` inherits
them from its base for the same reason it inherits the attributor. A stack
derived from the demo world must stay made of no-ops.
