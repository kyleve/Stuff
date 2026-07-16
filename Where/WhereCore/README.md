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
  implementation; `SwiftDataStore.inMemory()` backs tests and previews. It also
  holds the user's **tracked regions** (`trackedRegions()` /
  `setTrackedRegion(_:id:)`) — one synced row per region, defaulting to the four
  until the user chooses.
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

### Reads & aggregation

- **`ReportReader`** — the pure read path: `yearReport(for:)`, the year's raw
  manual entries `manualDays(inYear:)`, per-region `locations(in:year:)`, and
  `representativeCoordinates(for:)`.
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
  abrupt change) — the "Resolve" tab's detections and their `IssueResolution`
  fixes; dismissals persist under a stable, device- and timezone-independent
  `storageKey` (a `CalendarDay` ISO string), so a dismissal doesn't reappear
  after travel.
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
  reminder / summary schedules) behind a `KeyValueStore`.
- **`WhereLog`** — the Periscope logging facade: a `"Where"` root scope with
  grouping scopes (`location`, `reminders`, `backup`, `widgets`, …) and a typed
  `LogEvent` per collaborator, emitted into `Periscope.shared`.

## Installation

`WhereCore` is a local SPM library in this repo (`Where/WhereCore`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "WhereCore")])
```

## Quick start

Assemble a `WhereServices` (the app does this in its launch `open-store` step)
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

// Write a manual day (the caller supplies the ManualEntryAudit); the journal
// commits, then reconciles reminders + widgets.
try await services.journal.addManualDay(date: day, regions: [.california], audit: audit)

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

`InMemoryKeyValueStore` — a `KeyValueStore` test double for `WherePreferences` —
also ships here behind `@_spi(Testing)` (`#if DEBUG`); import it into test bundles
with `@_spi(Testing) import WhereCore`.
