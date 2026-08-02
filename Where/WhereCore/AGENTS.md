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
  `perform { … }` (the production store traps otherwise), and each committed
  transaction pings `changes()`. Never expose its `ModelContainer` through
  `WhereServices`; the separate DEBUG Inspector runtime uses
  `SwiftDataStore.makeContainer`, `inspectorModelTypes`, and
  `inspectorStoreURL` as its schema/storage adapter.
- **Each process opens its on-disk store once and injects it** — the app's
  launch opens it; the App Intents stack shares it via
  `WhereServices.forIntents(sharingStoreOf:)`. A second container over the
  same file is how a fresh install once raced the launch into failure (root
  [Composition](../../AGENTS.md#composition-create-once-inject-down)).
- **Primary regions *are* the tracked-region set.** `primaryRegions()` /
  `setPrimaryRegions(_:)` read/write the same `SDTrackedRegion` rows as
  `trackedRegions()` — picking scopes GPS attribution *and* carries each
  region's `RegionAppearance` + pick order. `RegionAppearance` is data
  (WhereCore); the token→`Color` mapping is presentation (WhereUI).
- **Backups mirror the persisted model — keep them lossless.** Any persisted
  change is reflected end-to-end: add it to `BackupArchive`, write it in
  `BackupService.makeArchiveFile`, read it back in
  `BackupCoordinator.importBackup` for **both** `.replace` and `.merge`, and
  add a round-trip test (`BackupServiceTests` / `BackupCoordinatorTests`).
  The archive is strict synthesized `Codable` — no in-code legacy decode; a
  shape change bumps `BackupArchive.currentFormatVersion` and extends
  [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb) instead.
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
  the current shape and drops (fault-logs) a row it can't place. The one-time
  reshape path is backup **export → transform
  ([`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb)) →
  replace-import**. Deliberate pre-release; the durable successor
  (per-entity schema versioning) is filed in [`../TODOs.md`](../TODOs.md).
- **Writes await their side effects.** `DayJournal` commits, then awaits the
  reminder reconcile + widget publish in sequence, so a reader on the next
  `changes()` ping never observes a half-applied write.
- **Post-write reconciliation is defined once.** Every write and import
  routes through `DayJournal.reconcileAfterDayChange()` (or its widget-less
  subset `reconcileIssueState()`) — never copy the fan-out into a new write
  path. Cross-collaborator hooks take a single closure wired at the
  composition root (`BackupCoordinator.onImport`).
- **Detectors read aggregated input; the speed-based one needs raw fixes.**
  `DataIssueInput.daySamples` carries per-day GPS fixes only (`.gpsVisit` /
  `.gpsSignificantChange`, sorted) — manual and evidence-implied samples are
  excluded so `FlightDayDetector`'s speed math isn't skewed.
- **`LocationSource` abstracts GPS** — `CoreLocationSource` in production,
  `ScriptedLocationSource` in tests/previews; `requestCurrentLocation()`
  returns `nil`, never throws, and backs
  `LocationIngestor.captureTodayIfNeeded(now:)`.
- **Tracked regions live in the store, not preferences** — one
  `SDTrackedRegion` row per region so cross-device edits merge; read as a
  `Set` defaulting to the four. `RegionAttribution` derives the attributor
  from them and rebuilds on `changes()`; assemble via the async
  `WhereServices.make(...)` / `forIntents()` so both attribute against the
  same synced set. `distanceToBoundary` is `nil` outside the tracked set.
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
