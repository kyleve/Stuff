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
  lives here — add behavior to `WhereCore` (rules + persistence)
  or `WhereUI` (views).
- **`WhereCore`** is the domain layer. It is pure Swift + Foundation +
  SwiftData + CoreLocation; it must not import SwiftUI or UIKit.
  Bundled region polygons (`Resources/*.geojson`) ship here.
- **`WhereUI`** is the SwiftUI layer. It depends on `WhereCore` and
  is what the app target imports.
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
      lifecycle (idempotent `start()` / `stop()`), the single-consumer
      sample stream, a bounded retry queue for transient persistence
      failures, and authorization.
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
  The one cross-collaborator op is `WhereServices.reset()` (stop GPS,
  then wipe the store) — the app's erase/teardown path.
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
  `europeanUnion`, `other`). Adding a region is intentionally a
  compile error in `Region.localizedName` until you add a matching
  string-catalog entry under
  [`Resources/Localizable.xcstrings`](WhereCore/Sources/Resources/Localizable.xcstrings).
- [`RegionAttributor`](WhereCore/Sources/RegionAttributor.swift) –
  maps `Coordinate` → `Region` via bundled GeoJSON
  ([`Resources/`](WhereCore/Sources/Resources/), see that folder's
  README for provenance). `RegionAttributor.shared` is the
  process-wide instance.
- [`Evidence`](WhereCore/Sources/Evidence/Evidence.swift) +
  [`EvidenceBlobStore`](WhereCore/Sources/Evidence/EvidenceBlobStore.swift)
  – metadata + externally-stored bytes for user-attached proofs
  (boarding passes, hotel receipts, …).

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
  production is CloudKit-synced.

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

All `WhereCore` `os.Logger` instances use subsystem
`"com.stuff.where"` with a per-type category. Match that when
adding new loggers so Console.app filtering stays consistent.

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
- Don't construct controllers, stores, or location sources inline. Pull
  fixtures from
  [`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift) —
  `loadedModel()`, `emptyModel()`, `elsewhereOnlyModel()`,
  `missingDaysModel()`, and `sampleReport()` are all synchronous, in-memory,
  and never touch disk, CloudKit, or CoreLocation. Add a new helper there
  rather than hand-rolling `WhereServices` in a `#Preview`.
- Views that read `WhereModel` from the environment need it injected:
  `.environment(PreviewSupport.loadedModel())` (or whichever model state the
  preview is exercising).
- Cover the states that matter, not just the happy path — empty, loaded, and
  any distinct edge state (e.g. missing-days, elsewhere-only) each deserve a
  preview when the view renders them differently.

## Adding things

- **New library target:** add to root
  [`Package.swift`](../Package.swift) under `Where/<Name>/Sources`,
  then wire a hosted test bundle in
  [`Project.swift`](../Project.swift) via the existing `unitTests`
  helper (`Where/<Name>/Tests/**`).
- **New region:** add the `Region` case, add a
  `Localizable.xcstrings` entry (the compiler will tell you),
  extend `RegionAttributor.usStateNames` or drop a new
  `<rawValue>.geojson` into
  [`Resources/`](WhereCore/Sources/Resources/), and add a
  `RegionAttributorTests` spot-check.
- **New evidence kind / sample source:** add the case, then update
  the exhaustive switches in `fromDiscriminator(...)` and the
  `knownCases` array — the compiler will surface every site that
  needs updating.
- **New SwiftUI view / widget:** add a `#Preview` in the same file (see
  [SwiftUI views & previews](#swiftui-views--previews)).

## Testing

- Use the `unitTests` helper in `Project.swift`; the test bundle
  runs in `StuffTestHost` and links `WhereTesting` automatically.
- Use `ScriptedLocationSource` to drive `WhereServices` (its
  `LocationIngestor`) from tests — never instantiate
  `CoreLocationSource` outside production wiring.
- Use `SwiftDataStore.inMemory()` for persistence tests so you
  never touch the user's on-disk / CloudKit store.
- UI tests that need a UIKit window go through `show(_:perform:)`
  from `WhereTesting`.
