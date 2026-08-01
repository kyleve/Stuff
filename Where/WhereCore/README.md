# WhereCore

The domain layer of the **Where** app: it ingests location, persists it, rolls
it up into per-day and per-year region presence, finds the data-quality problems
worth resolving, and drives the side effects that follow a change (reminders,
widget snapshots, backups, on-device activity summaries). It is pure Swift +
Foundation + SwiftData + CoreLocation + FoundationModels — **no SwiftUI or
UIKit** — so all of it is unit-testable off-screen. It builds on
[`RegionKit`](../RegionKit) for coordinate→region lookup and logs through
[`Periscope`](../../Shared/Periscope) via the `WhereLog` facade.

Everything is reached through one `Sendable` container, **`WhereServices`**,
which the presentation layer (`WhereUI`) and the widget extension talk to. For
the domain/presentation layering and the rules this module enforces, see the
feature [`Where/AGENTS.md`](../AGENTS.md); this file is the human-facing tour.

## What you get

`WhereServices` is a small struct of focused collaborators — add behavior to the
one it belongs to rather than to a god-object:

### Persistence & writes

- **`WhereStore`** — the value-type persistence boundary (a protocol; nothing
  crossing it is a SwiftData record). Mutations run inside `perform { … }` (one
  atomic transaction) and `changes()` emits once per commit and on a CloudKit
  remote import. `SwiftDataStore.make()` is the production, CloudKit-backed
  implementation; `SwiftDataStore.inMemory()` backs tests and previews. Each
  process opens its on-disk store **once** and injects it where it's needed —
  in the app, the launch's `resolve-scope` step opens it and the App Intents
  stack shares it via `WhereServices.forIntents(sharingStoreOf:)` — so two
  subsystems never race to create/open the same store file. It also
  holds the user's **tracked / primary regions** (`trackedRegions()` /
  `setTrackedRegion(_:id:)`, plus `primaryRegions()` / `setPrimaryRegions(_:)`
  which surface and persist each region's picked `RegionAppearance` — color
  token, emoji, SF Symbol — and pick order alongside the synced rows) — one row
  per region, defaulting to the four until the user chooses in the onboarding /
  Settings region picker.
- **`RegionAttribution`** — a live `RegionAttributing` built from the tracked
  regions that rebuilds on `changes()` (a local edit or a remote import), so the
  app + App Intents process attribute against the same synced set. Assemble
  services with `WhereServices.make(...)` (async — it reads the tracked set) in
  production; the synchronous `WhereServices.init` uses `RegionAttributor.shared`
  (the default four) for tests/previews.
- **`DayJournal`** — the user-sourced writes: manual-day overlays
  (`addManualDay` / `overrideDay` / `addManualDays`), clears
  (`clearManualDay` / `clearYear` / `eraseAllData`), evidence, and issue
  dismissals. Each write commits, then awaits its reminder reconcile + widget
  publish so the next reader sees a fully-applied change.

- **`DemoDataBuilder`** — writes the dataset the app's demo mode runs on into a
  given `WhereServices`: a plausible current year of living in New York with
  California trips, plus the backfills and corrected attributions a real year
  has and a few recent days still unlogged, so an empty app has something true
  to show. Bound to the current year and derived from it, so it stops at today
  and is the same every time. Every feature is sized against the *elapsed* part
  of the year, so a demo entered in January has the same shape as one entered in
  December.

### Reads & aggregation

- **`ReportReader`** — the pure read path: `yearReport(for:)`, the year's raw
  manual entries `manualDays(inYear:)`, per-region `locations(in:year:)`, and
  `representativeCoordinates(for:)`. `auditReport(for:)` returns a
  `YearAuditReport`: one consistent annual snapshot containing the finalized
  report, attributed samples, manual/evidence metadata, reporting timezone,
  tracked-region set, and boundary provenance. Production obtains its
  `YearAuditRecords` through one `SwiftDataStore` actor turn/read context and
  freezes the region set into an immutable attributor before computing rows and
  totals.
- **`YearReport` / `DayPresence` / `RegionDayLocations`** — the aggregated,
  snapshot-stable value types the UI renders, each keyed by a
  timezone-independent **`CalendarDay`** (`DayPresence.day`). A day counts for a
  region if *any* sample that calendar day fell inside it, so a single day can
  belong to several.
- **`CalendarDay`** — a Y-M-D value that is the stable identity of a logical day.
  Stored user records and day comparisons key on it so they don't drift onto a
  different day across a time-zone change; project to a concrete `Date` (grid
  layout, display) only via `startOfDay(in:)`.
- **`DayAggregator`** — turns samples + manual overlays into those reports,
  carrying the injected `Calendar` (which decides how a `sample.timestamp`
  buckets into a `CalendarDay`).

### Location

- **`LocationSource`** — the GPS abstraction: `CoreLocationSource` (Visits +
  significant-change) in production, `ScriptedLocationSource` in tests/previews.
  Passive `sampleStream` plus a best-effort one-shot `requestCurrentLocation()`
  (returns `nil`, never throws, when no fix is available).
- **`LocationIngestor`** — monitoring, the persist-with-retry queue, and
  authorization; after each committed sample it reconciles the badge/reminders
  and republishes the widget snapshot.

### Detection, notifications & the rest

- **`DataIssueScanner`** + the `DataIssue` family (missing days, border drift,
  abrupt change, flight days) — the "Resolve" tab's detections and their
  `IssueResolution` fixes; dismissals persist under a stable, device- and
  timezone-independent `storageKey` (a `CalendarDay` ISO string), so a dismissal
  doesn't reappear after travel. The `FlightDayDetector` reads the per-day GPS
  fixes the scanner puts on `DataIssueInput.daySamples` (timestamped, GPS-only)
  to spot cruise-speed points that added a spurious region. Each detector
  declares the category it finds (`DataIssueDetecting.detects`), which both
  labels its scan span and lets the scanner talk about categories without
  knowing the concrete detector types.
- **Reconcilers** — `ReminderReconciler` (daily logging reminder + app-icon
  badge), `DailySummaryReconciler` (year-to-date recap),
  `DataIssueAlertReconciler` ("issues to resolve").
- **`WidgetSnapshotPublisher`** — republishes the App Group snapshot the widgets
  read, with a freshness policy.
- **`BackupCoordinator`** — whole-database export / import (a ZIP archive, via
  `ZIPFoundation`).
- **`RecentActivitySummarizer`** — an on-device Foundation Models narrative over
  a selectable look-back `RecentActivityWindow`.
- **`WherePreferences`** — persisted user intent (onboarding, tracking intent,
  reminder / summary schedules) behind a `KeyValueStore`. The store has no
  default: production names `UserDefaults.standard` and everything else names
  `InMemoryKeyValueStore()`, so no test or preview can reach the host's real
  defaults by saying nothing.
- **`BuildInfo`** + **`AppAttribution`** — what Settings > About says about the
  bundle it is running in. `BuildInfo.current(bundle:)` reads the marketing
  version, build number, the commit the app was built from, and how the Swift
  compiler was invoked (`compilation`: configuration, optimization level,
  compilation mode) — `logSessionAttributes` hands that to a Periscope
  `LogSession` at launch, which is how a stored span duration can be told apart
  from one measured in an unoptimized build;
  `AppAttribution.main` reads the generated attribution report, decoding it once
  per process (`current(bundle:)` for any other bundle). Both return
  `nil`-shaped honesty for a bundle outside the app target, which carries
  neither. (The report's *format* and tooling are
  [`CreditKit`](../../Shared/CreditKit/README.md)'s; data-source provenance is
  [`RegionKit`](../RegionKit/README.md)'s.)
- **`WhereLog`** — the Periscope logging facade: a `"Where"` root scope with
  grouping scopes (`location`, `reminders`, `backup`, `widgets`, `reporting`, …)
  and a typed `LogEvent` per collaborator, emitted into `Periscope.shared`. Each
  collaborator's expensive work is also timed against a declared budget through
  its `*Log`'s `SpanName` cases, so slow reads, commits, and reconciles show up
  in Periscope's span history rather than only as a slow screen.

## Installation

`WhereCore` is a local SPM library in this repo (`Where/WhereCore`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "WhereCore")])
```

## Quick start

Assemble a `WhereServices` (the app does this in its launch `resolve-scope` step)
and talk to the collaborators:

```swift
import WhereCore

// Production wiring reads the tracked regions from the store to build the
// attributor, so `make(...)` is the one public entry and is async. Tests and
// previews use the synchronous `@_spi(Testing)` `init` instead (an explicit
// attributor, default four) via `@_spi(Testing) import WhereCore`.
let services = try await WhereServices.make(
    store: try SwiftDataStore.make(),   // production; use .inMemory() in tests
    locationSource: CoreLocationSource(),
)

// Read a year, aggregated with the injected calendar + region attribution.
let report = try await services.reports.yearReport(for: 2026)

// Read a transparent audit snapshot whose source rows and totals share one
// captured attribution policy.
let annualAuditReport = try await services.reports.auditReport(for: 2026)

// Write a manual day (the caller supplies the ManualEntryAudit); the journal
// commits, then reconciles reminders + widgets.
let manualEntryAudit = ManualEntryAudit(
    recordedAt: Date(),
    note: "Backfilled from travel records.",
    location: nil,
)
try await services.journal.addManualDay(
    date: day,
    regions: [.california],
    audit: manualEntryAudit,
)

// Refresh whenever anything changes — local edits, live GPS, or a synced import.
for await _ in services.dataChangeUpdates() {
    // re-read whatever you display
}
```

## How it works

A single **read-refresh signal** ties the module together: every write origin —
a manual edit, a live GPS sample, or a CloudKit import from another device —
funnels through `WhereStore.perform` (or the remote-import path) and pings
`changes()`. Readers (the UI's session, the issue scanner) re-derive purely off
that ping, so nothing goes stale behind a write it didn't initiate; and because
writes await their own side effects, a reader on the next ping sees a
fully-applied change. `WhereServices.reset()` is the one inherently
cross-collaborator operation — it quiesces GPS ingestion *before* wiping the
store so the retry queue can't repopulate it mid-erase.

## Contracts & limitations

- **Values, not records.** Nothing crossing `WhereStore` is a SwiftData object;
  the live `ModelContainer` is surfaced only for the read-only debug inspector.
- **Always-location.** Background day tracking needs Always; `requestPermission()`
  throws `LocationPermissionDeniedError` on denial / restriction.
- **Failures surface.** Store methods are `async throws`; errors are logged via
  `WhereLog` and left observable — never swallowed into an empty default.
- **Foundation Models may be unavailable.** `RecentActivitySummarizer` reports a
  typed reason rather than a silently empty summary.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in `StuffTestHost`.
Use `SwiftDataStore.inMemory()` + `ScriptedLocationSource` — never the
on-disk/CloudKit store or `CoreLocationSource`. The CloudKit remote-import path
is exercised via the `@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`.

`InMemoryKeyValueStore` — a `KeyValueStore` for `WherePreferences` that keeps
everything in memory — is plain `public` API, as are the noop schedulers and
refreshers. They back tests and previews, but they ship because the app's demo
mode is built out of them.

They are also what the `@_spi(Testing)` `WhereServices.init` defaults its
notification and widget seams to, so a test or preview that names nothing
posts nothing and reloads nothing. The public `WhereServices.make(...)`
requires those seams instead: naming the real world is the composition root's
job, not something a caller falls into by omission.
