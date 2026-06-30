# Where – Feature Shape

Where is an iOS/iPadOS/macOS app for answering "what
region was I in on which day?" It ingests passive
GPS (Visits + significant-change), accepts user-asserted history
(manual coordinates, whole-day overlays, evidence like boarding
passes), and rolls everything up into per-day region presence and
per-year reports. The primary use case is residency / day-count
audits, so a day "counts" for a region if **any** sample in that
calendar day fell inside the region's polygon (a single day can
belong to multiple regions, e.g. a CA→NY same-day flight).

This file complements the root [`AGENTS.md`](../AGENTS.md), which
owns build system, formatting, and global conventions. Read that
first.

## Modules

```
Where/
  Where/         App target – SwiftUI entry point (WhereApp → RootView)
  WhereCore/     SPM library – domain model, persistence, GPS, aggregation
  WhereUI/       SPM library – SwiftUI views (depends on WhereCore)
  WhereTesting/  SPM library – iOS test host helpers (show(), waitFor, ...)
```

- **App target** `Where` ([`Project.swift`](../Project.swift),
  bundle ID `com.stuff.where`) is intentionally tiny: it wires
  `RootView` from `WhereUI` into a `WindowGroup`. Almost no logic
  lives here — add domain behavior to `WhereCore`, presentation and
  view-model wiring to `WhereUI`.
- **`WhereCore`** is the domain layer. It is pure Swift + Foundation +
  SwiftData + CoreLocation; it must not import SwiftUI or UIKit.
  Bundled region polygons (`Resources/*.geojson`) ship here.
- **`WhereUI`** is the SwiftUI layer: views plus `@Observable` view
  models (`WhereModel`, `WhereSession`) that mirror service state and
  expose UI intent methods. It depends on `WhereCore` and is what the
  app target imports. It is **not** the domain model — see [Layering](#layering).
- **`WhereTesting`** is a UIKit-only helper library for hosted unit
  tests (`show(_:perform:)`, `waitFor(...)`, `recursiveDescription`).
  It is meant for test bundles, not production code.

Tests live under each module's `Tests/` (Swift Testing only, never
XCTest — see the root rules).

## Key types in `WhereCore`

Public surface is small and `Sendable`; values cross the persistence
boundary, never SwiftData records.

- [`WhereServices`](WhereCore/Sources/WhereServices.swift) –
  the feature's service layer: a small `Sendable` container assembled
  once by `WhereBootstrap` that composes a `WhereStore` and a
  `LocationSource` into focused collaborators. Use this as the entry
  point — don't talk to the store or location source directly from UI.
  Collaborators (each `WhereCore`, unit-tested in isolation):
    - `ReportReader` (`struct`) – pure reads: `yearReport`, location
      projections.
    - `LocationIngestor` (`actor`) – live GPS ingestion: the monitoring
      lifecycle (idempotent `start()` / `stop()`, plus `quiesce()` that stops
      the source and drains any in-flight persist for a clean erase), the
      single-consumer sample stream, a bounded retry queue for transient
      persistence failures, and authorization.
    - `DayJournal` (`actor`) – user-sourced writes: manual days, range
      backfills, overrides, clears, evidence — each followed by its
      reminder reconcile + widget publish.
    - `ReminderReconciler` / `DailySummaryReconciler` (`actor`s) – the
      notification intent + badge/schedule (and recap-body)
      reconciliation.
    - `WidgetSnapshotPublisher` (`actor`) – owns the published widget
      snapshot + the rebuild/throttle policy.
    - `BackupCoordinator` (`actor`) – backup export/import
      (`ImportStrategy` / `ImportSummary` live here).
    - [`DataIssueScanner`](WhereCore/Sources/DataResolution/DataIssueScanner.swift)
      (`actor`) – scans the year report + raw samples for fixable data
      quality issues (missing days, GPS border drift, abrupt location
      changes). Owns detection I/O, a ~3h throttle/cache keyed by
      `(year, driftThresholdMeters, calendar day)` — the calendar day is part
      of the key so a midnight rollover recomputes the day-relative missing-days
      backlog cutoff even mid-throttle, without callers tracking the rollover —
      and sorting; exposes
      `issues(year:primaryRegions:driftThresholdMeters:force:)` and
      `invalidate()`. Subscribes to the store-change signal (`store.changes()`,
      passed at init) and drops its cache on every committed write, so a
      non-forced read can't serve a stale scan after a background GPS ingest or
      remote sync. Detectors implement [`DataIssueDetector`](WhereCore/Sources/DataResolution/DataIssueDetector.swift)
      (typed `Issue` per detector, erased to `[any DataIssue]` for the
      UI). Dismissals are read from the store and filtered out before
      return. `WhereServices.reset()` calls `await resolution.invalidate()`.
  The one cross-collaborator op is `WhereServices.reset()` (quiesce GPS
  ingestion, then wipe the store) — the app's erase/teardown path.
- [`LocationSample`](WhereCore/Sources/LocationSample.swift) +
  [`SampleSource`](WhereCore/Sources/LocationSample.swift) – the
  atomic observation unit. `SampleSource` distinguishes
  GPS / manual / evidence-implied origins.
- [`DayPresence`](WhereCore/Sources/DayPresence.swift) /
  [`YearReport`](WhereCore/Sources/YearReport.swift) – aggregated
  output of [`DayAggregator`](WhereCore/Sources/DayAggregator.swift)
  (pure, no I/O).
- [`Region`](WhereCore/Sources/Region.swift) – the closed set of
  tracked regions (`california`, `newYork`, `canada`,
  `europeanUnion`, `other`). Two exhaustive switches make adding a
  region a compile error until resolved: `Region.localizedName`
  (needs a matching string-catalog entry under
  [`Resources/Localizable.xcstrings`](WhereCore/Sources/Resources/Localizable.xcstrings))
  and `Region.geometrySource` (the single source of truth for where a
  region's polygons come from — `.usStateFeature(name:)`, `.bundledFile`,
  or `.none`).
- [`RegionAttributor`](WhereCore/Sources/RegionAttributor.swift) –
  maps `Coordinate` → `Region` via bundled GeoJSON
  ([`Resources/`](WhereCore/Sources/Resources/), see that folder's
  README for provenance). Loads polygons in `Region.allCases` order
  (which fixes first-match priority) driven entirely by each region's
  `geometrySource`. `RegionAttributor.shared` is the process-wide
  instance.
- [`RegionGeometryCatalog`](WhereCore/Sources/RegionGeometryCatalog.swift) –
  read-only, off-main API behind the developer region-map viewer. Its
  `outlines(for:)` returns drawable `RegionOutline`s (exterior ring +
  title + optional `Region`) for either `.attribution` (what
  `RegionAttributor` loaded) or `.source` (every authored GeoJSON
  feature, cached). UI consumes outlines via this catalog, never the raw
  `RegionPolygons`/`GeoJSON` internals.
- [`Evidence`](WhereCore/Sources/Evidence/Evidence.swift) +
  [`EvidenceBlobStore`](WhereCore/Sources/Evidence/EvidenceBlobStore.swift)
  – metadata + externally-stored bytes for user-attached proofs
  (boarding passes, hotel receipts, …).
- **Data resolution** ([`DataResolution/`](WhereCore/Sources/DataResolution/))
  – [`DataIssue`](WhereCore/Sources/DataResolution/DataIssue.swift) protocol +
  per-detector issue types (`MissingDaysIssue`, `BorderDriftIssue`,
  `AbruptChangeIssue`), closed [`IssueResolution`](WhereCore/Sources/DataResolution/DataIssue.swift)
  enum (backfill / relabel / mark-travel-day), and [`DriftThreshold`](WhereCore/Sources/DataResolution/DataIssue.swift)
  (persisted via `WherePreferences.driftThresholdMeters`, default 1 km). UI
  switches on `IssueResolution`, not detector types. `BorderDriftIssue` covers
  both a day attributed *only* to `.other` and a *mixed* day where a real
  region also picked up a stray `.other` (GPS jitter across a border); its
  relabel resolution suggests the day's real regions, dropping only the
  spurious `.other`.
- [`GeoPolygon`](WhereCore/Sources/GeoPolygon.swift) – planar polygon
  geometry used by `RegionAttributor`; exposes
  `distanceToBoundary(from:)` for border-drift detection.
- [`LongitudeSpan`](WhereCore/Sources/LongitudeSpan.swift) – the shortest
  longitudinal arc enclosing a set of longitudes, **antimeridian-aware**
  (a cluster straddling ±180° like Alaska's Aleutians frames as a tight
  arc, not a near-global span). The region-map viewer pairs it with
  `BoundingBox` (latitude) to frame its camera.

### Persistence

- [`WhereStore`](WhereCore/Sources/Persistence/WhereStore.swift)
  – protocol boundary. All mutations MUST be inside a
  `perform { ... }` block (the block owns the write transaction);
  the production store traps otherwise.
- [`SwiftDataStore`](WhereCore/Sources/Persistence/SwiftDataStore.swift)
  – `@ModelActor` SwiftData implementation. The auto-generated
  main context is treated as read-only; each outermost `perform`
  spins up a peer `ModelContext` for batched writes (commit on
  success, discard on throw, nested `perform`s coalesce).
  Storage modes: `.inMemory` / `.localOnly` / `.cloudKit`, with
  `.default` auto-picking based on test env + `#if DEBUG` —
  production is CloudKit-synced. Record types include
  `SDDismissedIssue` (CloudKit-synced dismissal keys for the Resolve
  tab; included in backup export/import via `BackupArchive.dismissedIssues`,
  round-tripped as `DismissedIssue` value types preserving `dismissedAt`).
- **Store-change signal.** [`WhereStore.changes()`](WhereCore/Sources/Persistence/WhereStore.swift)
  returns a fresh `AsyncStream<Void>` that pings once after every committed
  `perform` and on a CloudKit remote import — the single read-refresh signal
  every write origin (manual edit, live GPS, remote sync) funnels through.
  `SwiftDataStore` owns a [`StoreChangeBroadcaster`](WhereCore/Sources/StoreChangeBroadcaster.swift)
  (per-subscriber fan-out) that `perform` pings on commit, plus a
  [`StoreRemoteChangeSource`](WhereCore/Sources/Persistence/StoreRemoteChangeSource.swift)
  seam — production `PersistentStoreRemoteChangeSource` observes
  `.NSPersistentStoreRemoteChange`; tests wire the `@_spi(Testing)`
  `ScriptedStoreRemoteChangeSource` and call `yield()`. The wiring is folded
  into the factories (`make` for CloudKit, `inMemory(remoteChangeSource:)` for
  tests), so there's no public `startObservingRemoteChanges` to call twice.
  `WhereServices.dataChangeUpdates()` re-exposes the stream for the view-model
  (see [Layering](#layering)).

### GPS

- [`LocationSource`](WhereCore/Sources/Location/LocationSource.swift)
  – `AnyObject` protocol exposing an `AsyncStream<LocationSample>`.
  Production is
  [`CoreLocationSource`](WhereCore/Sources/Location/CoreLocationSource.swift)
  (Visits + significant-change, requires Always authorization).
  Tests/previews wire `ScriptedLocationSource` and call `emit(_:)`
  to push samples.
- `LocationPermissionDeniedError` is the hard-failure signal — surface
  a Settings deep-link rather than silently degrading.

### Logging

All logging goes through
[`WhereLog`](WhereCore/Sources/WhereLog.swift), the central facade over
[`LogKit`](../Shared/LogKit). Get a logger with
`WhereLog.channel(_:)`, passing a typed `WhereLog.Category` rather than a
raw string — add a case there to introduce a new category (its raw value
is the Console.app category, all under subsystem `"com.stuff.where"`).
Each `LogChannel` fans out to `os.Logger` (Console.app) and, in DEBUG
builds, into the process-wide `WhereLog.store` buffer the in-app log
viewer reads (Settings → Developer → Logs, DEBUG only — see
[`LogViewerUI`](../Shared/LogViewerUI)). Messages are plain `String`s, so
per-argument `os` privacy annotations are not available; the facade logs
as `.public`, so keep PII out of log messages.

Level semantics: `info` marks the **success of an important operation**
(session lifecycle, year loaded, tracking started/stopped, store opened,
backup export/import, widget published); `warning` marks a
**degraded-but-handled** state the app recovered from (When-In-Use/denied
location, retry-queue saturation, missing Application Support or backup
asset, reminders/summary enabled without notification authorization);
`error`/`fault` stay reserved for outright failures. `warning` maps to
`OSLogType.default`, so it shows as a distinct level in the in-app viewer
without inflating Console's error-level queries. There is no fine-grained
`.debug` tracing on the hot paths (per-GPS-sample persist, per-day reminder
scheduling, widget throttle/skip) — those stay quiet by design.

## Localization

All user-facing copy resolves through module string catalogs — no literals in
views or thrown errors.

- **WhereUI:** funnel every string through
  [`Strings.swift`](WhereUI/Sources/Shared/Strings.swift), which looks up keys
  in [`Resources/Localizable.xcstrings`](WhereUI/Sources/Resources/Localizable.xcstrings)
  with `bundle: .module`. Counts use catalog plural variations; years use a
  grouping-free number style so they read "2026", not "2,026".
- **WhereCore:** user-visible errors and region names use static
  `String(localized:bundle: .module)` keys in
  [`Resources/Localizable.xcstrings`](WhereCore/Sources/Resources/Localizable.xcstrings)
  (see `Region.localizedName` — add a case + key when adding a region).
- **DEBUG-only UI** (Settings → Developer links, inspector labels) still gets
  catalog entries — don't bypass localization because a surface is dev-only.
- **WhereWidgets:** gallery name/description live in the extension's own
  `Localizable.xcstrings` (see [`WhereWidgets/AGENTS.md`](WhereWidgets/AGENTS.md));
  in-widget copy reuses WhereUI `Strings`.

When adding copy, add the key to the catalog first, then reference it from
`Strings` or Core — never ship English literals in SwiftUI `Text` or
`errorDescription`.

## Calendar, dates & presentation

### Calendar and date ranges

- **Year bounds are half-open.** `DayAggregator.yearInterval(year:)` spans
  `[Jan 1 year, Jan 1 year+1)` in the aggregator's calendar/time zone; store
  filters use `timestamp >= start && timestamp < end` so Jan 1 of the next year
  is never double-counted.
- **Day ranges are inclusive.** `Date.calendarDays(through:in:)` normalizes
  both endpoints to start-of-day and walks `first ... last` inclusively; an
  empty range means `end` fell before `start`.
- **Inject `Calendar`, don't reach for globals.** Logged-in UI reads
  `WhereSession.calendar` (Gregorian, current time zone); layout types like
  `CalendarMonth` carry the calendar they were built with. Prefer
  `calendar.component(...)` and `calendar.range(of:in:for:)` over hardcoding
  `7` weekdays or day counts.
- **Core layout APIs throw on failure.** When calendar metadata can't be derived
  (e.g. weekday count), throw rather than silently returning a default — callers
  surface `ContentUnavailableView` and log, not `!`.

### WhereUI presentation helpers

- **Layout constants → [`UIConstants`](WhereUI/Sources/Shared/UIConstants.swift).**
  Spacing, padding, corner radii, and one-off sizes live there — not magic
  numbers sprinkled through views.
- **Shared date-range copy → [`DateRangeFormatting`](WhereUI/Sources/Shared/DateRangeFormatting.swift).**
- **Numbers and dates → `FormatStyle` / formatters**, not string interpolation.
- **Expensive layout belongs in state.** Calendar months, filtered lists, and
  similar work compute once into `@State` or the view model and invalidate on
  input changes — don't rebuild on every `body` pass (same idea as
  `LogViewerModel`'s cached `filteredEntries`).
- **Missing data in views → `ContentUnavailableView` + log**, not force-unwrap.
- **Sharing files → `ShareLink` / `Transferable`**, not custom
  `UIActivityViewController` wiring unless the platform API truly can't handle
  the payload.

## Layering

Where splits **domain** from **presentation**. Keep the split sharp when adding
features — views should not grow business logic just because SwiftUI makes it
easy.

| Layer | Where | Owns |
|-------|-------|------|
| **Domain / services** | `WhereCore` (`WhereServices` collaborators) | Rules, detection, aggregation, persistence, side effects (reminders, widgets, backup). Unit-test here. |
| **View model** | `WhereUI` (`WhereSession`, `WhereModel`) | Lifecycle wiring, observable mirrors of service output, UI intent methods (`refresh()`, `dismiss(_:)`, `select(year:)`). Orchestrates `WhereServices`; does not reimplement Core rules. |
| **Views** | `WhereUI` (`*View`) | Layout, navigation, localized copy, bindings to session/model. Calls view-model methods; does not talk to the store, run detection, or own cache/throttle policy. |

**Data resolution** is the reference shape: `DataIssueScanner` + detectors live in
Core; `WhereSession.refreshDataIssues` / `dismiss(_:)` mirror and trigger;
[`ResolutionView`](WhereUI/Sources/Resolution/ResolutionView.swift) only lists,
routes by `IssueResolution`, and forwards dismiss.

**One read path.** Every committed write emits a single store-change signal
(`WhereStore.changes()`), and readers refresh purely off it rather than at each
write site. `WhereSession.observeDataChanges()` subscribes to
`services.dataChangeUpdates()` and re-pulls its report + data-issue scan on every
ping; `DataIssueScanner` drops its cache on the same signal. So the write intent
methods (`setManualDay`, `overrideDay`, …) just commit — they don't refresh
inline — and live GPS ingestion and CloudKit remote imports refresh the UI the
same way a manual edit does. `select(year:)` / `appBecameActive()` still refresh
explicitly (navigation / lifecycle, not writes).

When in doubt: if the behavior would still be correct without SwiftUI, it
belongs in `WhereCore` (or, for logged-in orchestration that exists only to
serve the UI, on `WhereSession` — still not in a `View`).

## View models & launch (`WhereUI`)

`WhereUI` hosts the SwiftUI shell and **view models** — not the domain model.
Launch is driven by [`LifecycleKit`](../Shared/LifecycleKit) (read its
[`AGENTS.md`](../Shared/LifecycleKit/AGENTS.md) for the engine).

- [`WhereModel`](WhereUI/Sources/Model/WhereModel.swift) (`@MainActor
  @Observable`) – app-level view model: the onboarding gate, persisted
  `WherePreferences`, and an **optional** `WhereSession`. Lives for the whole
  process and is built *before* the store opens so a background relaunch can
  wire CoreLocation first.
- [`WhereSession`](WhereUI/Sources/Model/WhereSession.swift) (`@MainActor
  @Observable`) – logged-in view model over a **non-optional** `WhereServices`:
  `selectedYear`, `report`, `loadState`, tracking/authorization, reminder +
  summary settings, backup, **data issues**. Created by the launch's
  `open-store` step (`startSession()`), dropped on reset (`endSession()`), and
  read by logged-in views via `@Environment(WhereSession.self)` — so there are
  no `guard let session` checks sprinkled through the UI.   Exposes intent
  methods that delegate to Core (`refresh()` → `ReportReader`, `dismiss(_:)` →
  `DayJournal` + `DataIssueScanner`, etc.) and holds thin mirrors (e.g.
  `dataIssues` from `services.resolution.issues(...)`). A long-lived
  `observeDataChanges()` (wired into `start()` and the `syncAuth` launch step
  alongside the authorization observer) subscribes to the store-change signal
  and re-pulls report + data issues, so write intents just commit without
  refreshing inline (see [One read path](#layering)).
- [`WhereLaunch`](WhereUI/Sources/Launch/WhereLaunch.swift) – assembles the
  cold-launch `LifecycleSteps` and its reverse `resetSequence` (erase + reset),
  with steps named by the typed `LaunchStepID` enum (a parity test guards step
  order against `WhereSession.start()`). The nested `WhereBootstrap` owns the
  service assembly: `prepareLocation()` runs as the runner's synchronous
  `initializePrerequisites` (installs `CLLocationManager` so a queued background
  event isn't lost), and `makeServices()` opens the store off the main actor.
- [`RootView`](WhereUI/Sources/RootView.swift) wraps the real `TabView` in a
  `LifecycleContainer`, gating `enterForeground()` on `scenePhase == .active` so
  a headless background launch stays UI-less. Tabs: Primary, Calendar,
  **Resolve** ([`ResolutionView`](WhereUI/Sources/Resolution/ResolutionView.swift)
  — missing days, border drift, abrupt changes; badge shows
  `session.dataIssueCount`), Settings.
  [`AppDelegate`](Where/Sources/AppDelegate.swift) picks the `LifecycleReason`
  from `launchOptions` and drives the runner.

## SwiftUI views & previews

Every previewable component in `WhereUI` (any `View`, `Widget`, or
`WidgetBundle`) **must** ship at least one `#Preview` in the same file — a
hard rule, checked before the component is done. Previews are our fastest
visual regression check and double as living documentation of each view's
states.

- Wrap previews in `#if DEBUG ... #endif` and place them at the bottom of
  the file (see
  [`RegionSummaryCard.swift`](WhereUI/Sources/Primary/RegionSummaryCard.swift)
  for the canonical shape).
- Don't construct services, stores, or location sources inline. Pull
  fixtures from
  [`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift) —
  `loadedSession()`, `emptySession()`, `elsewhereOnlySession()`,
  `missingDaysSession()`, `resolutionSession()`, `loadedModel()`, and
  `sampleReport()` are all synchronous, in-memory, and never touch disk,
  CloudKit, or CoreLocation. Add a new helper there rather than hand-rolling
  `WhereServices` in a `#Preview`.
- Inject whatever the view reads from the environment: logged-in views read
  `@Environment(WhereSession.self)`, so pass a `*Session()` fixture
  (`.environment(PreviewSupport.loadedSession())`); the app-level shell
  (onboarding, Settings reset) reads `WhereModel`, so pass
  `.environment(PreviewSupport.loadedModel())`.
- Cover the states that matter, not just the happy path — empty, loaded, and
  any distinct edge state (e.g. missing-days, elsewhere-only) each deserve a
  preview when the view renders them differently.

## Developer tools

- [`RegionMapView`](WhereUI/Sources/Developer/RegionMapView.swift) draws
  region boundary polygons on a real map with a segmented toggle between
  `.attribution` (what `RegionAttributor` loaded) and `.source` (every
  authored GeoJSON feature), reading geometry from
  [`RegionGeometryCatalog`](WhereCore/Sources/RegionGeometryCatalog.swift).
  It is **self-contained** — no `@Environment(WhereSession.self)` — so the
  same view backs both the DEBUG-only Settings → Developer → Region map entry
  and the standalone `RegionViewer` Mac Catalyst app. Geometry decodes off
  the main thread (the catalog is `async`); a decode failure lands in a
  `.failure` state (and the logs), never a silently empty map.
- Map views bridge model `Coordinate`s to MapKit with the shared
  [`Coordinate.clLocationCoordinate`](WhereUI/Sources/Shared/Coordinate+MapKit.swift)
  extension (`Coordinate` itself stays CoreLocation-free in the model layer).

## Adding things

- **New library target:** add to root
  [`Package.swift`](../Package.swift) under `Where/<Name>/Sources`,
  then wire a hosted test bundle in
  [`Project.swift`](../Project.swift) via the existing `unitTests`
  helper (`Where/<Name>/Tests/**`).
- **New region:** add the `Region` case, then resolve the two
  compile errors it forces: a `localizedName` `Localizable.xcstrings`
  entry, and a `Region.geometrySource` case declaring where its
  polygons come from — `.usStateFeature(name:)` (a feature already in
  `us-states.geojson`, no new file) or `.bundledFile` (drop a new
  `<rawValue>.geojson` into
  [`Resources/`](WhereCore/Sources/Resources/)). `RegionAttributor`
  loads it automatically from `geometrySource`; add a
  `RegionAttributorTests` spot-check.
- **New evidence kind / sample source:** add the case, then update
  the exhaustive switches in `fromDiscriminator(...)` and the
  `knownCases` array — the compiler will surface every site that
  needs updating.
- **New SwiftUI view / widget:** add a `#Preview` in the same file (see
  [SwiftUI views & previews](#swiftui-views--previews)).
- **New app icon:** run `./icons --add <1024.png> --name <Name>` (see the
  root [`AGENTS.md`](../AGENTS.md#managing-app-icons)) — it updates both asset
  catalogs and `AppIcons.json`. Don't hand-edit those; the picker is
  manifest-driven.

## Testing

- Use the `unitTests` helper in `Project.swift`; the test bundle
  runs in `StuffTestHost` and links `WhereTesting` automatically.
- Use `ScriptedLocationSource` to drive `WhereServices` (its
  `LocationIngestor`) from tests — never instantiate
  `CoreLocationSource` outside production wiring.
- Use `SwiftDataStore.inMemory()` for persistence tests so you
  never touch the user's on-disk / CloudKit store. To exercise the
  remote-import (CloudKit sync) path off-device, use the `@_spi(Testing)`
  `SwiftDataStore.inMemory(remoteChangeSource:)` with a
  `ScriptedStoreRemoteChangeSource` and drive it via `yield()` — both reached
  through `@_spi(Testing) @testable import WhereCore`.
- UI tests that need a UIKit window go through `show(_:perform:)`
  from `WhereTesting`.
- **Split tests when sources split** — e.g. each
  [`DataIssueDetector`](WhereCore/Sources/DataResolution/DataIssueDetector.swift)
  gets its own `*Tests.swift`; shared clocks/builders live in
  `*TestSupport.swift`, not copied across files.
- **Wait for conditions** (`waitFor`, `waitUntil`, `renders(within:_:)` from
  WhereTesting / LifecycleKit test support) instead of fixed run-loop iterations.
- **Inject production limits in tests** — e.g. `LocationIngestor` retry-queue
  capacity via `@_spi(Testing)` with a small value, not the live 1000-cap.
- Non-obvious detectors and geometry helpers get a **brief doc comment** on the
  type (what it detects / key invariants) — see existing
  [`DataIssueDetector`](WhereCore/Sources/DataResolution/DataIssueDetector.swift)
  implementations.
