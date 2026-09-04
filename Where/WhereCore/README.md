# WhereCore

The domain layer of the **Where** app: it ingests location, persists it, rolls
it up into per-day and per-year region presence, finds the data-quality problems
worth resolving, and drives the side effects that follow a change (reminders,
widget snapshots, backups). It is pure Swift + Foundation + SwiftData +
CoreLocation — **no SwiftUI or UIKit** — so all of it is unit-testable off-screen. It builds on
[`RegionKit`](../RegionKit) for coordinate→region lookup and logs through
[`Periscope`](../../Shared/Periscope) via the `WhereLog` facade.

Automatic backups keep the existing inner backup schema intact, then encrypt
that ZIP with AES-256-GCM inside a `.wherebackup` envelope. A synchronized
Keychain recovery key protects the payload; `AutomaticBackupStorage` prefers
iCloud Drive, falls back to app Documents, and retains the newest three
recognized automatic files. Manual exports remain plaintext ZIPs.

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
  atomic transaction); callers whose decision was made against a particular
  data generation use `perform(expectedDataGenerationID:)`, and multi-table reads use
  `readSnapshot { … }` so a Reset or Replace cannot split one operation across
  generations; a persistent-history boundary invalidates any external commit
  crossing a snapshot even when its remote-change notification arrives later.
  `changes()` emits once per local commit and external import for the Where store
  URL, excluding other stores such as Periscope. `remoteChanges()` uses
  persistent-history transaction authors to emit only the external-import subset,
  so headless notifications and widgets rebuild without duplicating local work.
  `SwiftDataStore.make(storage:)` opens an explicitly selected
  CloudKit, local-only, or in-memory store; `SwiftDataStore.inMemory()` is the
  convenience used by tests and previews. Each
  process opens its on-disk store **once** and injects it where it's needed —
  in the app, the launch's `resolve-scope` step opens it and the App Intents
  stack shares it via `WhereServices.forIntents(sharingStoreOf:)` — so two
  subsystems never race to create/open the same store file. It also
  holds the user's **tracked / primary regions** (`trackedRegions()` /
  `setTrackedRegion(_:id:)`, plus `primaryRegions()` / `setPrimaryRegions(_:)`
  which surface and persist each region's picked `RegionAppearance` — color
  token, emoji, SF Symbol — and pick order alongside the synced rows) — one row
  per region, defaulting to the four until the user chooses in the onboarding /
  Settings region picker. Recording identity and synced status are split into
  immutable profiles, append-only nickname events and removal tombstones, and target-owned
  advisory check-ins rather than one mutable device row. Recording consent stays local.
- **`WhereDataGeneration`** — the account-wide logical generation that keeps late
  uploads from an offline device from repopulating data after Reset or Replace.
  Each destructive operation appends one immutable node naming every real
  maximal generation it observed. Reset wins a concurrent Replace; multiple unjoined
  resets resolve to a deterministic empty UUIDv8 synthetic generation, so neither
  reset branch's rows can reappear before another operation causally joins them. Persisted
  event ids remain UUIDv4; UUIDv8 is reserved for resolver-derived generations.
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

- **`ReportReader`** — the pure read path: `yearReport(for:)`, the one-read
  `yearReportDetails(for:primaryRegionCount:)` bundle used by the scene, the
  year's raw manual entries `manualDays(inYear:)`, single- or multi-region
  `locations(in:year:)` projections, and `representativeCoordinates(for:)`.
  `YearReportDetails` keeps the aggregate report and its primary-region raw
  locations on the same samples snapshot, including location-only changes that
  do not alter day totals.
- **`YearReport` / `YearReportDetails` / `DayPresence` /
  `RegionDayLocations`** — the aggregated, snapshot-stable value types the UI
  renders, each keyed by a
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
  and republishes the widget snapshot. Every automatic sample is stamped with
  the current installation's `RecordingDeviceID`. Every durable retry entry
  also carries the data generation that authorized it, so a pre-reset fix can be
  discarded but never written into the replacement generation.
- **`LocationOutbox`** — a backup-excluded, JournalKit-backed sidecar for samples
  SwiftData could not commit. It appends complete bounded queue snapshots, so a
  crash-torn final write falls back to the preceding intact state; Reset and
  Replace durably checkpoint an empty queue before deleting its raw bytes.
- **`DeviceRecordingController`** — applies this installation's local automatic-recording
  preference and persisted current-On cutoff to its physical `LocationIngestor`, so a late visit
  from an Off interval remains rejected after relaunch. Immutable profiles, nickname events,
  target-owned advisory check-ins, and global removal tombstones sync independently. Another
  installation can rename or remove a device identity, but cannot change its recording consent.
- **`LocationHistoryReader`** — the shared removal-aware read boundary used by reports, widgets,
  and foreground capture checks. It hides a removed identity's GPS samples at
  and after its earliest tombstone while keeping earlier raw storage, backups, legacy samples
  without provenance, and user-asserted samples lossless.

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
- **`BackupCoordinator`** — ZIP export/import via `ZIPFoundation`. Export pins
  tables and evidence blobs to one generation-consistent snapshot. Merge preserves queued locations
  and the installation-local recording choice. Replace writes the archive into a new child generation,
  retains existing removal tombstones, and preserves the local choice before pending fixes are
  discarded. A prepared
  marker in the backup-excluded installation
  sidecar pairs with a receipt committed in the same store transaction as the archive;
  recreated services can therefore distinguish rollback from commit and gate further
  onboarding until cleanup succeeds. Import is onboarding-only; Settings exposes export without
  another live-session transaction path. Onboarding acknowledgement records an independent terminal
  sidecar tombstone before clearing recovery, so a cold launch can repair a preference write
  that did not reach disk without offering the same archive again.
  Check-ins are deliberately neither exported nor restored because they are live advisory status.
- **`InstallationRecordingContext`** — the device-local installation identity,
  explicitly confirmed local recording choice, and stable timestamp for recreating
  its immutable device profile idempotently.
  `InstallationRecordingContextStoring` keeps the persistence adapter outside
  the domain value.
- **`WherePreferences`** — persisted user intent (onboarding,
  reminder / summary schedules, Locations-card GPS-dot visibility) plus the
  year-keyed Location-card counts used for presentation continuity, behind a
  `KeyValueStore`. The store has no
  default: production names `UserDefaults.standard` and everything else names
  `InMemoryKeyValueStore()`, so no test or preview can reach the host's real
  defaults by saying nothing. Recording confirmation is deliberately absent:
  it lives beside the non-backed-up installation identity instead.
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
    store: try SwiftDataStore.make(storage: .cloudKit),
    locationSource: CoreLocationSource(),
    installationContext: installationContext, // resolved once by the app composition root
)

// Read a year, aggregated with the injected calendar + region attribution.
let report = try await services.reports.yearReport(for: 2026)

// Read the scene's aggregate and primary-region recorded fixes together.
let details = try await services.reports.yearReportDetails(
    for: 2026,
    primaryRegionCount: 2,
)

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
fully-applied change. Generation-pinned snapshots keep a multi-table projection in
one generation, while expected-generation writes reject work whose assumptions went
stale across a suspension. `WhereServices.reset()` is the one inherently
cross-collaborator operation — it reversibly pauses ingestion, atomically
rotates to a Reset child generation, and discards the retry queue only after commit.

## Contracts & limitations

- **Values, not records.** Nothing crossing `WhereStore` is a SwiftData object;
  the DEBUG Inspector runtime opens its own container directly from the same
  schema factory and uses the factory's exact store URL for recovery, without
  constructing `WhereServices`.
- **Always-location.** Background day tracking needs Always; `requestPermission()`
  throws `LocationPermissionDeniedError` on denial / restriction.
- **Removal is global; recording consent is local.** A synced removal tombstone immediately hides
  the target identity's samples at and after its timestamp and makes that installation stop when
  it next observes the change. Turning recording on or off affects only the installation where
  the user made the choice. Device check-ins are advisory status, not command acknowledgements;
  Apple Lost Mode or remote erase remains the security boundary for a missing device. Account
  Reset also retires an installation registered before its causal reset boundary, even when that
  installation's profile did not reach the resetting device until later.
- **Destructive operations are logical generations.** Old rows may remain in
  CloudKit as sync/audit history, but ordinary reads select only the resolved
  generation. Concurrent unjoined resets select a synthetic empty generation; an
  incomplete causal generation DAG fails closed instead of mixing old and new state.
- **Failures surface.** Store methods are `async throws`; errors are logged via
  `WhereLog` and left observable — never swallowed into an empty default.
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
