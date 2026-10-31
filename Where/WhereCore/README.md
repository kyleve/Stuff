# WhereCore

The domain layer of the **Where** app: it ingests location, persists it, rolls
it up into per-day and per-year region presence, finds the data-quality problems
worth resolving, and drives the side effects that follow a change (reminders,
widget snapshots, backups). It is pure Swift + Foundation + SwiftData +
CoreLocation — **no SwiftUI or UIKit** — so all of it is unit-testable off-screen. It builds on
[`RegionKit`](../RegionKit) for coordinate→region lookup and logs through
[`Periscope`](../../Shared/Periscope) via the `WhereLog` facade.

Services are reached through one `Sendable` container, **`WhereServices`**,
which the presentation layer (`WhereUI`) and App Intents use. The widget
extension reads published App Group snapshots without opening the store. For
the domain/presentation layering and the rules this module enforces, see the
feature [`Where/AGENTS.md`](../AGENTS.md). This file is the human-facing tour.

## What you get

`WhereServices` is a small struct of focused collaborators — add behavior to the
one it belongs to rather than to a god-object:

### Persistence & writes

- **`WhereStore`** — the value-type persistence boundary (a protocol; nothing
  crossing it is a SwiftData record). Mutations run inside `perform { … }` (one
  atomic transaction). Callers whose decision was made against a particular
  data generation use `perform(expectedDataGenerationID:)`, and multi-table reads use
  `readSnapshot { … }` so a Reset or Replace cannot split one operation across
  generations. A persistent-history boundary invalidates any external commit
  crossing a snapshot even when its history observer reports the change later.
  `changes()` emits once per local commit and external import for the Where model
  container, excluding other stores such as Periscope. `remoteChanges()` uses
  SwiftData's `HistoryObserver` and persistent-history transaction authors to
  emit only the external-import subset,
  so headless notifications and widgets rebuild without duplicating local work.
  `SwiftDataStore.make(storage:)` opens an explicitly selected CloudKit,
  local-only, or in-memory store. On-disk modes carry their App Group identifier;
  the host chooses that policy and group, so WhereCore contains no audience
  default. `SwiftDataStore.inMemory()` is the convenience used by tests and
  previews. Each
  process opens its on-disk store **once** and injects it where it's needed —
  in the app, the launch's `resolve-scope` step opens it and the App Intents
  stack shares it via `WhereServices.forIntents(sharingStoreOf:)` — so two
  subsystems never race to create/open the same store file. It also
  holds the user's **tracked / primary regions** (`trackedRegions()` /
  `setTrackedRegion(_:id:)`, plus `primaryRegions()` / `setPrimaryRegions(_:)`
  which surface and persist each region's picked `RegionAppearance` — color
  token, emoji, typed `RegionSymbol` — and pick order alongside the synced rows) — one row
  per region, defaulting to the four until the user chooses in the onboarding /
  Settings region picker. Recording identity and synced status are split into
  immutable profiles, append-only nickname events and removal tombstones, and target-owned
  advisory check-ins rather than one mutable device row. Recording consent stays local.
- **`WhereDataGeneration`** — the account-wide logical generation that keeps late
  uploads from an offline device from repopulating data after Reset or Replace.
  Each destructive operation appends one immutable node naming every real
  maximal generation it observed. Reset wins a concurrent Replace. Multiple unjoined
  resets resolve to a deterministic empty UUIDv8 synthetic generation, so neither
  reset branch's rows can reappear before another operation causally joins them. Persisted
  event ids remain UUIDv4. UUIDv8 is reserved for resolver-derived generations.
- **`RegionAttribution`** — a live `RegionAttributing` built from the tracked
  regions that rebuilds on `changes()` (a local edit or a remote import), so the
  app + App Intents process attribute against the same synced set. Assemble
  services with `WhereServices.make(...)` (async — it reads the tracked set) in
  production. The synchronous `WhereServices.init` uses `RegionAttributor.shared`
  (the default four) for tests/previews.
- **`DayJournal`** — the user-sourced writes: manual-day overlays
  (`addManualDay` / `overrideDay` / `addManualDays`), clears
  (`clearManualDay` / `clearYear` / `eraseAllData`), evidence, and issue
  dismissals. Writes await reminder/issue reconciliation and widget publication
  after committing. The local fan-out does not yet refresh daily summaries;
  that gap is tracked in [`../TODOs.md`](../TODOs.md).
- **`PlannedStayCoordinator`** — stores independent travel plans and an optional forecast home
  region. Each plan has a stable identity and inclusive arrival and departure windows.
  `create(_:)`, `update(_:)`, and `delete(stayID:)` affect one plan. Completed plans remain
  available. `snapshot()` reads plans and the home choice from one store snapshot.
  `setHomeRegion(_:)` assigns unplanned days to that region; nil selects historical estimates.
  This choice does not change tracked regions or recorded presence. Turning estimate display off
  does not remove plans. Each register resolves synced revisions by timestamp, then revision UUID.
  Deletion and historical selection retain tombstones to prevent stale imports from restoring old intent.
- **`PlannedStayLocationVerifier`** — gets a current location and compares it with the selected
  region. The configured drift threshold expands the accepted area outside the region boundary.
  A missing location or missing geometry returns an unavailable result.
  The itinerary editor does not request location verification.
- **`CurrentRegionResolver`** — returns a typed live-region resolution only
  while automatic recording is authorized. A successful decision requires a
  fix no more than 60 seconds old, with valid horizontal accuracy at or below
  1 km, inside a tracked region, and farther from its boundary than the fix's
  uncertainty radius. Its measured outcome logs contain only reason codes and
  coarse age/accuracy buckets.

- **`DemoDataBuilder`** — writes the dataset the app's demo mode runs on into a
  given `WhereServices`: a plausible current year of living in New York with
  California trips, plus the backfills and corrected attributions a real year
  has. Its configuration independently includes missing-day, border-drift,
  abrupt-change, and detected-flight fixtures; unchecked detector categories
  stay absent. The standard onboarding demo includes missing days. Bound to the
  current year and derived from it, so it normally stops at today and is the
  same every time. During the first days of January, its in-memory clock moves
  forward only far enough to hold the selected fixtures. Every feature is sized against the *elapsed* part
  of the year, so a demo entered in January has the same shape as one entered in
  December.

### Reads & aggregation

- **`ReportReader`** — the pure read path: `yearReport(for:)`, the one-read
  `yearReportDetails(for:)` bundle used by the scene, the
  year's raw manual entries `manualDays(inYear:)`, single- or multi-region
  `locations(in:year:)` projections, and `representativeCoordinates(for:)`.
  `YearReportDetails` keeps the aggregate report, configured primary set, effective
  locations, and `ElsewhereInput` on one store snapshot. Its identity includes
  location-only changes that do not alter day totals.
- **`ElsewhereResolver`** — an injected actor that lazily resolves ordinary Other
  coordinates against the existing catalog. Its `ElsewhereReport` keeps distinct
  days and map points together. Explicit corrections and manual assertions win.
  The projection does not change stored data, annual reports, or widget totals.
- **`YearReport` / `YearReportDetails` / `DayPresence` /
  `RegionDayLocations`** — the aggregated, snapshot-stable value types the UI
  renders, each keyed by a
  timezone-independent **`CalendarDay`** (`DayPresence.day`). A day counts for
  each region in its effective sample attribution after removal visibility and
  GPS corrections, plus additive manual entries. An authoritative manual overlay
  replaces that presence.
  A single day can belong to several regions; raw observations remain lossless.
- **`CalendarDay`** — a Y-M-D value that is the stable identity of a logical day.
  Stored user records and day comparisons key on it so they don't drift onto a
  different day across a time-zone change. Project to a concrete `Date` (grid
  layout, display) only via `startOfDay(in:)`.
- **`DayAggregator`** — turns samples + manual overlays into those reports,
  carrying the injected `Calendar` (which decides how a `sample.timestamp`
  buckets into a `CalendarDay`).
- **`PresenceCalendar` / `CalendarMonth`** — lays a report out into month grids
  and preserves both ranked per-region totals and exact multi-region
  combination totals for accessible month summaries.

### Location

- **`LocationSource`** — the GPS abstraction: `CoreLocationSource` (Visits +
  significant-change) in production, `ScriptedLocationSource` in tests/previews.
  Passive `sampleStream` plus a bounded one-shot `requestCurrentLocation()`
  whose nonthrowing result distinguishes permission, precision, timeout,
  provider, and cancellation outcomes. Concurrent one-shot callers coalesce;
  cancellation removes only that caller. Cached callbacks must pass the
  one-minute freshness gate before satisfying them. The one-shot request targets
  100 m accuracy to improve attribution near borders, while the live-region
  decision still has a hard 1 km uncertainty cap. The system-facing one-shot
  controls use `CurrentLocationRequestDriving`; tests substitute a driver fake
  while retaining the same request coordinator. Its idle/pending state owns the
  coalesced waiters and timeout as one request.
- **`LocationIngestor`** — monitoring, the persist-with-retry queue, and
  authorization. After each committed sample it reconciles the badge/reminders
  and republishes the widget snapshot. Every automatic sample is stamped with
  the current installation's `RecordingDeviceID`. Every durable retry entry
  also carries the data generation that authorized it, so a pre-reset fix can be
  discarded but never written into the replacement generation.
- **`LocationOutbox`** — a backup-excluded, JournalKit-backed sidecar for samples
  SwiftData could not commit. It appends complete bounded queue snapshots, so a
  crash-torn final write falls back to the preceding intact state. Reset and
  Replace durably checkpoint an empty queue before deleting its raw bytes.
- **`DeviceRecordingController`** — applies this installation's local automatic-recording
  preference and persisted current-On cutoff to its physical `LocationIngestor`, so a late visit
  from an Off interval remains rejected after relaunch. Immutable profiles, nickname events,
  target-owned advisory check-ins, and global removal tombstones sync independently. Another
  installation can rename or remove a device identity, but cannot change its recording consent.
  `devices()` supplies active device configurations. `displayNames()` supplies the latest saved names,
  including removed devices, for historical labels.
- **`LocationHistoryReader`** — the shared removal-aware read boundary used by reports, widgets,
  and foreground capture checks. It hides a removed identity's GPS samples at
  and after its earliest tombstone while keeping earlier raw storage, backups, legacy samples
  without provenance, and user-asserted samples lossless.

### Detection, notifications & the rest

- **`DataIssueScanner`** — publishes a coherent revision of actionable issues,
  informational GPS reviews, and the next reassessment deadline. Committed raw
  evidence invalidates its cache even when day/region totals remain equal.
  Missing-day and abrupt-change detection share the same snapshot; flight and
  boundary cleanup use one sample assessment. Supported flight transitions stay
  in that review instead of producing a separate whole-day abrupt-change suggestion.
  Pending flights remain reviewable without adding to correction badges or notifications.
  A pending flight does not block another completed flight's corrections, including flights on the same day.
  One daily review can offer completed-flight edits and retain pending flight information.
  Applying or dismissing those edits leaves the pending flight review available without an actionable count.
  Dismissing a ready suggestion with no pending flights hides its review and live notice.
  `DataIssueScanResult.completedFlights` retains historical flights independently of review dismissal.
  `FlightAssessment.completedDays(in:)` includes only days covered by supported travel intervals.
  Unsupported gaps and later ground observations do not add flight days.
  Calendar builders accept these days through their explicit `flightDays` argument.
  Pending and completed informational reviews remain accessible.
- **`FlightTrajectoryAnalyzer`** — a pure, per-device GPS analysis before day
  bucketing, with 24 hours of report-boundary context. It uses independent fixes
  at least 60 seconds apart, positional uncertainty, sustained jet-speed progress,
  turning departure/approach segments, and an observed ground dwell. Flight-only
  types live in [`DataResolution/Flights`](Sources/DataResolution/Flights).
  [`GPSCorrectionPolicy`](Sources/DataResolution/GPSCorrectionPolicy.swift) names
  the shared inference limits: three anchors spanning three minutes, with each
  leg's uncertainty-adjusted average speed at 450–1,500 km/h. Arrival requires
  three ground anchors spanning ten minutes within 2 km and at most 50 km/h.
  `FlightGroundInference` also accepts bounded sparse stationary observations and measured slow ground travel.
  The policy keeps their duration, gap, accuracy, and sensor requirements explicit.
  `FlightAssessment.RecordingSource` separates identified installations from legacy samples.
  `Reassessment` distinguishes a scheduled refresh from an evidence-driven refresh.

  `FlightAssessment.Progress.completed` carries typed `Arrival` evidence, including its confirmation time.
  Ground first observed over 30 minutes after supported travel produces `uncertainTiming`.
  That flight remains in history. Only independently supported airborne points remain eligible for exclusion.
  Existing exclusions in the arrival gap remain reversible through restoration-only reviews, without adding flight days.
  `supportedIntervals` retains observed motion and corroborated displacement separately.
  `supportedPeriods` coalesces touching intervals for display without filling gaps.

  A qualifying ground episode confirms the trip ended. The 30-minute freshness limit
  only changes live-notice presentation. Cruise inference uses positional
  movement. Reported speed can veto ground dwell, and altitude is context only.
  Missing or stale updates never establish arrival. Slower aircraft and uncorroborated
  recordings can remain uncertain.

  `FlightDisplacementInference` also recognizes sparse journeys from distance and elapsed time.
  Both endpoints need independent nearby observations from the same recording device.
  The search spans intervening fixes and stops at confirmed ground episodes.
  Recognition accepts up to 1 km horizontal uncertainty; observed cruise and point corrections retain the 250 m limit.
  Travel must span at least five minutes, with an uncertainty-adjusted average speed of 450–1,500 km/h.
  Speed comes from the distance and elapsed time between positions, including both endpoints' uncertainty.
  The gap must not exceed 18 hours. Each supporting observation must be within 30 minutes and 100 km of its endpoint.
  It must also be closer to its own endpoint than the opposite endpoint after uncertainty is included.
  This prevents alternating short GPS jumps from corroborating one another.

  Conflicting dense callbacks veto this inference. Reported speed and altitude are not required.
  Stationary speed readings at the endpoints do not describe the travel between them.
  This evidence joins observed cruise segments before arrival and trip boundaries are resolved.
  It establishes flight history without classifying the gap or its endpoints as airborne.
  Automatic point exclusions still require observed cruise evidence. Explicit reviewed point decisions remain available after confirmed arrival.

  `FlightEndpointInference` can corroborate a resumed cruise endpoint through
  reported speed or a bounded recording gap followed by sustained cruise.
  Slow sensor readings veto this inference. The gap remains unknown and never
  becomes an observed motion leg. Each inferred endpoint carries its reason
  into the correction review.

  `FlightTrajectoryGenerator` builds synthetic journeys and then simulates GPS observations.
  The analyzer tests run 1,000 fixed seeds per profile by default: 12,000 journeys across twelve profiles.
  These include short sparse flights and stationary journeys with brief clusters of remote GPS errors.
  Replay a failure with
  `TEST_RUNNER_WHERE_FLIGHT_FUZZ_PROFILE` and `TEST_RUNNER_WHERE_FLIGHT_FUZZ_SEED`.
  Run the suite with `./test --only WhereCoreTests/FlightTrajectoryAnalyzerTests`.
  Use `TEST_RUNNER_WHERE_FLIGHT_FUZZ_COUNT` to override the count for a focused run.
  Failures report the seed, sampling parameters, and synthetic trace.
  Recorded regressions use the [flight fixture export procedure](#recorded-flight-fixtures).
- **`SampleCorrectionAssessment`** — shares the raw-evidence assessment for flights
  and border drift. Its named policy includes 24-hour report context and local
  boundary brackets within ten minutes on each side. These conservative limits
  leave longer gaps uncorrected because they can hide real travel.
  Proposals carry a GPS-only `Kind` and order edits by timestamp, then sample identity.
  Each reviewed day produces at most one actionable issue.
- **`SampleCorrectionCoordinator`** — reviews exact GPS edits and reassesses them
  in the guarded store transaction before Apply. Any changed evidence refreshes
  the review instead of expanding the reviewed sample set. Supported airborne
  points can be excluded only after arrival. A boundary relabel needs local
  same-device brackets in the retained region within ten minutes on both sides.
  Manual assertions, unknown fixes, ground endpoints, layovers, and later
  destinations retain their contributions. Reviews coalesce identical synced rows
  by sample identity; conflicting representations remain uncorrected.
  A `FlightPointCorrection` lets the user explicitly include or restore one GPS point within a completed flight.
  Both actions recheck the same evidence and data generation as automatic proposals.
  Restoration writes a reset revision. It preserves the original GPS sample and the earlier correction history.
  `LocationHistoryReader.projection`
  joins lossless raw samples to the effective attribution for reports, maps,
  artwork, widgets, summaries, reminders, and intents.
- **`SampleAttributionRevision`** — an immutable, generation-scoped sample register,
  resolved by timestamp then UUID. Its dedicated `ID` preserves the bare UUID backup format.
  Correction and reset writes share a timestamp helper that advances observed history by at least one millisecond.
  A nil replacement restores GPS attribution,
  an empty set excludes the sample, and a populated set replaces its regions.
  Reset to GPS clears the day's manual override and writes newer tombstones in
  one transaction. Revisions can arrive before their samples; device-removal
  filtering takes precedence.
- **Reconcilers** — `ReminderReconciler` (daily logging reminder + app-icon
  badge), `DailySummaryReconciler` (year-to-date recap),
  `DataIssueAlertReconciler` ("issues to resolve").
- **`WidgetSnapshotPublisher`** — republishes the App Group snapshot the widgets
  read, with a freshness policy for the independently aggregated data.
- **`WidgetPresentationPublisher`** — atomically writes the device-local `WhereTheme`
  to its own App Group file and reloads WidgetKit without reading or rebuilding widget data.
- **`BackupCoordinator`** — ZIP export/import via `ZIPFoundation`. Export pins
  tables, planned-stay and home-region revisions, sample-attribution revisions, and evidence blobs
  to one generation-consistent snapshot. Merge preserves queued locations
  and the installation-local recording choice. Replace writes the archive into a new child generation,
  retains existing removal tombstones, and preserves the local choice before pending fixes are
  discarded. A prepared
  marker in the backup-excluded installation
  sidecar pairs with a receipt committed in the same store transaction as the archive. 
  recreated services can therefore distinguish rollback from commit and gate further
  onboarding until cleanup succeeds. Import is onboarding-only. Settings exposes export without
  another live-session transaction path. Onboarding acknowledgement records an independent terminal
  sidecar tombstone before clearing recovery, so a cold launch can repair a preference write
  that did not reach disk without offering the same archive again.
  Check-ins are deliberately neither exported nor restored because they are live advisory status.
  Backup format **v8** retains independent stays, date windows, Home choices, optional motion,
  every sample-attribution revision, recording ownership grants, recovery exclusions, and the compatibility floor.
  Merge preserves revision IDs and timestamps.
  Replace restores revisions into its new generation.
  The offline [`upgrade-backup.rb`](../Tools/upgrade-backup.rb) command upgrades earlier archives.
  Legacy stay revisions retain one shared identity, including deletion tombstones.
  The converter infers arrival from each revision's UTC date, capped at its final day.
  The production decoder accepts only the current format. See [backup format](BACKUP_FORMAT.md).
  Export before upgrading the app. Upgrade the archive offline, then replace-import it.
  Update every syncing installation before editing plans. Older builds use a single
  stay register and can delete independent stays in the shared store.
- **`InstallationRecordingContext`** — the device-local identity, confirmation state,
  and stable device-profile timestamp. `confirmInitialRecording` returns
  `ConfirmedInstallationContext`, whose choice is Off or On with its consent date.
  Recording services require this confirmed type. `confirmed()` throws when a
  restored installation still needs a choice. The persistence adapter remains
  behind `InstallationRecordingContextStoring`.
- **`WherePreferences`** — persisted user intent (onboarding,
  reminder / summary schedules, presentation theme, and Locations-card GPS-dot,
  live-region welcome, and estimated-time/planning visibility) plus the
  year-keyed Location-card counts, welcome history, and recording-warning generation used for presentation
  continuity, behind a `KeyValueStore`. Missing welcome history requires a quiet initial baseline.
  Calendar zoom choices use caller-supplied `CalendarZoomKey` namespaces. Your Year and each
  region have independent keys. Missing or invalid entries leave the caller's initial mode intact.
  `reset()` clears every calendar zoom namespace, including custom keys.
  An explicit developer reset retains a history value with no region, which permits a greeting.
  These preferences stay outside the backup archive. The former welcome-region key does not seed the new history.
  It also owns the vendor-neutral
  `DiagnosticReportingConfiguration`: crash reports default On, replay Off,
  and remote logs Off in Release / Warning in Debug. `WherePreferences` encodes
  this configuration directly. Invalid data keeps the channel defaults. Invalid data
  also turns remote logging Off. Reset removes every reporting key. Release always reduces
  diagnostic export to baseline fields. Export policies retain independent, extensible controls.
  The legacy full-metadata preference grants only the four named built-in controls.
  `RecordingConfigurationWarningCondition` evaluates the live
  device authority, recording choice, and authorization tuple in Core. The store has no
  default: production names `UserDefaults.standard` and everything else names
  `InMemoryKeyValueStore()`, so no test or preview can reach the host's real
  defaults by saying nothing. Recording confirmation is deliberately absent:
  it lives beside the non-backed-up installation identity instead.
- **Installer updates** — `BuildInfo.distribution` exposes InstallerKit's signed
  `InstalledBuild` only for the Development audience, including explicitly configured local builds.
  `WherePreferences` implements
  `UpdatePreferencesStoring` with a device-local `installerUpdates` value.
  [InstallerKit](../../Shared/InstallerKit/README.md) owns catalog validation,
  update selection, request throttling, and cache policy.
- **`BuildInfo`** + **`AppAttribution`** — what Settings > About says about the
  bundle it is running in. `BuildInfo.current(bundle:)` reads the marketing
  version, build number, the commit the app was built from, and how the Swift
  compiler was invoked (`compilation`: configuration, optimization level,
  compilation mode) — `logSessionAttributes` hands that to a Periscope
  `LogSession` at launch, which is how a stored span duration can be told apart
  from one measured in an unoptimized build. 
  `AppAttribution.main` reads the generated attribution report, decoding it once
  per process (`current(bundle:)` for any other bundle). Both return
  `nil`-shaped honesty for a bundle outside the app target, which carries
  neither. (The report's *format* and tooling are
  [`CreditKit`](../../Shared/CreditKit/README.md)'s. data-source provenance is
  [`RegionKit`](../RegionKit/README.md)'s.)
- **`WhereLog`** — the Periscope logging facade: a `"Where"` root scope with
  grouping scopes (`location`, `reminders`, `backup`, `widgets`, `reporting`, …)
  and an `@LogScope` namespace per collaborator. Nested `@LogEvent` structs emit through generated classified methods into `Periscope.shared`. Each
  collaborator's expensive work is also timed against a declared budget through
  its `*Log`'s `SpanName` cases, so slow reads, commits, and reconciles show up
  in Periscope's span history rather than only as a slow screen.
  Span-only collaborators such as `ReportReaderLog` declare an `@LogScope`
  enum with a nested `SpanName`; they need no event declaration or empty payload.

Where's structured failure events use restricted `LogError` payloads.
Callers pass the original error through `.restricted(.errorDetails, error)`.
The snapshot preserves typed diagnostics without a duplicate error attachment.
Local messages use the snapshot's description. Severities remain unchanged.
Events converted from error strings use payload version 2 and an `error` field.
Baseline export excludes their errors. Diagnostic export filters each structured snapshot using its field controls.
See [PeriscopeCore's error contract](../../Shared/Periscope/PeriscopeCore/README.md#structured-errors).

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
// The bootstrap has already checked compatibility and created these dependencies.
let services = try await WhereServices.make(
    store: try await compatibility.openDomainStore(),
    locationSource: locationSource,
    installationContext: try installationContextStore.resolve().confirmed(),
    recordingAuthority: recording,
    deviceCoordination: recording,
    reminderScheduler: reminderScheduler,
    summaryScheduler: summaryScheduler,
    issueAlertScheduler: issueAlertScheduler,
    widgetRefresher: widgetRefresher,
    importRecoveryPersistence: installationContextStore
)

// Read a year, aggregated with the injected calendar + region attribution.
let report = try await services.reports.yearReport(for: 2026)

// Read the scene's aggregate and primary-region recorded fixes together.
let details = try await services.reports.yearReportDetails(for: 2026)

// Resolve named non-primary visits when the Elsewhere tab needs them.
let elsewhere = try await services.elsewhere.resolve(details.elsewhereInput)

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
that ping, so nothing goes stale behind a write it didn't initiate. Because
writes await their own side effects, a reader on the next ping sees a
fully-applied change. Generation-pinned snapshots keep a multi-table projection in
one generation, while expected-generation writes reject work whose assumptions went
stale across a suspension. `WhereServices.reset()` is the one inherently
cross-collaborator operation — it reversibly pauses ingestion, atomically
rotates to a Reset child generation, and discards the retry queue only after commit.

## Contracts & limitations

- **Values, not records.** Nothing crossing `WhereStore` is a SwiftData object.
  The DEBUG Inspector runtime opens its own container directly from the same
  schema factory and uses the factory's exact store URL for recovery, without
  constructing `WhereServices`.
- **Always-location.** Background day tracking needs Always. `requestPermission()`
  throws `LocationPermissionDeniedError` on denial / restriction.
- **Removal is global. Recording consent is local.** A synced removal tombstone immediately hides
  the target identity's samples at and after its timestamp and makes that installation stop when
  it next observes the change. Turning recording on or off affects only the installation where
  the user made the choice. Device check-ins are advisory status, not command acknowledgements. 
  Apple Lost Mode or remote erase remains the security boundary for a missing device.
  Reset clears history while retaining installation identity, consent, ownership, and the
  compatibility floor. Historical account-reset events keep their original retirement semantics.
- **Destructive operations are logical generations.** Old rows may remain in
  CloudKit as sync/audit history, but ordinary reads select only the resolved
  generation. Concurrent unjoined resets select a synthetic empty generation. An
  incomplete causal generation DAG fails closed instead of mixing old and new state.
- **Failures surface.** Store methods are `async throws`. Errors are logged via
  `WhereLog`. Most callers propagate failure or retain honest failed state.
  The reminder badge still logs a failed scan and returns zero; that exception
  is tracked in [`../TODOs.md`](../TODOs.md).
## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in `StuffTestHost`.
Use `SwiftDataStore.inMemory()` + `ScriptedLocationSource` for domain tests.
Do not open the user's on-disk/CloudKit store or make live Core Location requests.
Production-source history tests use isolated temporary on-disk containers without
CloudKit (`StoreRemoteChangeSourceTests`).
`CoreLocationSourceTests` exercises the one-shot coordinator with an injected
`CurrentLocationRequestDriving` fake, without starting passive monitoring.
The CloudKit remote-import path
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

Calendar-day persistence keys use `CalendarDay.iso8601` (`YYYY-MM-DD`); diagnostic `description` is not a storage API.

### Recorded flight fixtures

The recorded corpus covers sparse displacement, legacy recordings with mixed sampling, interrupted cruise with a turning approach, and late cruise resumption.
Each JSON fixture in `Tests/Fixtures/Flights/` retains its complete selected window, including ground travel and duplicate callbacks.
The analyzer regressions check flight recognition, positive arrival evidence, supported days, and protection of ground points.
They also check reordered delivery, repeated callbacks, and removal of arrival evidence.

The recorded cruise regression checks live progress, stale observations, and arrival confirmation from successive callback prefixes.
`RecordedFlightArchiveFixture` packages that complete window with replacement device metadata and fixed test regions.
The correction regression imports this archive, applies reviewed exclusions, and checks the report and preservation of ground points and raw samples.
These checks run in ordinary CI without a private backup or replay configuration.

`RecordedFlightFixture` uses synthesized `Codable` with the existing `LocationSample` representation.
Its JSON contains `coordinates` (`rotated` or `original`), `now`, and the ordered `samples` array.
Fixture dates use Foundation's default Codable representation: seconds since January 1, 2001 UTC.
This representation preserves timestamp precision without conversion to another epoch.
The encoder preserves nonfinite sensor values as `NaN`, `Infinity`, or `-Infinity` strings.
The JSON contains observations only. Swift tests keep the independently reviewed expectations.
`Project.swift` copies the `Flights` folder into `WhereCoreTests.xctest`, including for CI workers that receive prebuilt products.
A missing or malformed fixture throws an error.

```swift
let fixture = try RecordedFlightFixture.load(.sparse)
let flights = FlightTrajectoryAnalyzer().analyze(samples: fixture.samples, now: fixture.now)
```

`FlightFixtureExporterTests.exportArchiveFixtureOnRequest` extracts GPS callbacks from a current-format backup through `BackupService`.
It applies device-removal cutoffs and selects the half-open interval `[from, until)`.
It retains callback order, duplicates, conflicting identities, accuracy, motion readings, and device boundaries.
Manual and evidence-derived samples are outside this GPS-only fixture.

The exporter replaces sample and device IDs and shifts every timestamp by one constant.
By default, it rotates all coordinates together. The rotation preserves spherical distances, including across the date line and near the poles.
The optional `coordinateMode` accepts `rotate` or `preserve`. Preserve mode copies the original coordinates exactly, so RegionKit attribution and boundary distances remain unchanged.
Both modes omit the input path and replace IDs. The JSON `coordinates` field identifies whether coordinates are original or rotated.
The date shift depends on `replacementStart`; coordinate preservation does not disable it.
Route shape, timing, accuracy, and sensor values remain recognizable characteristics. Review the output before publishing it.

1. Keep the backup and export configuration outside the checkout.
   Upgrade an old backup with [`upgrade-backup.rb`](../Tools/upgrade-backup.rb) first.
2. Select a window with departure support, arrival observations, and any relevant layover.
   Keep the complete window before reducing a failure to a smaller example.
3. Save a local JSON configuration. Dates are Unix seconds. This example uses invented dates and paths:

   ```json
   {
     "backupPath": "/private/tmp/where-backup.zip",
     "from": 1767225600,
     "until": 1767312000,
     "now": 1767398400,
     "replacementStart": 1577836800,
     "replacementOrigin": {"latitude": 15, "longitude": -30},
     "outputPath": "/private/tmp/sparse-flight.json"
   }
   ```

   For original coordinates, add `"coordinateMode": "preserve"` and remove `replacementOrigin`.
   For rotation, omit `coordinateMode` or set it to `"rotate"`, and supply `replacementOrigin`.
   The exporter rejects a missing rotation origin or an origin supplied with preserve mode.
   Preserve mode publishes the selected coordinates unchanged in the JSON file.

4. Run from the repository root:

   ```sh
   TEST_RUNNER_WHERE_FLIGHT_FIXTURE_EXPORT_CONFIG=/private/tmp/flight-export.json \
     ./test --only WhereCoreTests/FlightFixtureExporterTests
   ```

   The export stops if transformation or JSON decoding changes flight recognition, arrival evidence, supported intervals, or correction identities.
   It also refuses to overwrite an existing output file.
   These checks verify transformation fidelity. They do not establish the correct flight result.
5. Review the generated JSON file. For calendar failures, select a replacement date that retains the relevant boundary.
   Coordinate rotation does not preserve country or state attribution. Use preserve mode when a regression needs the original RegionKit geometry.
6. Copy the reviewed JSON file into `Tests/Fixtures/Flights/`.
   Add its filename stem to `RecordedFlightFixture.Name`.
   Add a named regression in `FlightTrajectoryAnalyzerTests.swift` with independently reviewed expectations.
   Assert flight count, arrival evidence, supported days, airborne identities, and protected ground points as applicable.
   Use `sparse-flight.json` and `recordedSparseFlightRetainsRecognitionWithoutInventingAirbornePoints` as an example.
7. Run `./test --only WhereCoreTests/FlightTrajectoryAnalyzerTests` with the export configuration unset.
   The bundled JSON fixture runs in ordinary CI without the private archive or export configuration.

## Recording authority

The [recording authority guide](RECORDING_AUTHORITY.md) explains the state model,
conditional server writes, retry outcomes, local reconciliation, and review order.

CloudKit authority records decide who owns recording. `SDRecordingAuthorityCommit`
records what this device learned. `CloudKitRecordingAuthorityRecord` owns the
typed head/event identities and payload coding inside the transport boundary.
`RecordingAuthority` distinguishes `.unclaimed` from `.established(Established)`.
An established value always has an owner and revision. Every proposal returns
that narrower type. Its `Transition.recover` case carries the required history choice.
`RecordingAuthorityRecord` retains the existing synthesized JSON shapes and
validates them before constructing domain values. Domain enums are not serialized.
`EventID`, `OwnershipID`, and `RequestID` are distinct types. A creating transition
uses its event UUID to identify the new grant or request. The persisted
`store://recording-authority/<uuid>` spelling stays unchanged.

`RecordingAuthorityCoordinator` reconciles a server-confirmed owner and data
version into the existing store. `RecordingDeviceCoordination` owns explicit role
selection and durable transition retries. `DeviceRecordingController` permits
automatic GPS only for the designated owner with local recording consent.
Pausing recording leaves ownership unchanged. Secondary devices can still request
a one-shot location for a manual action.

```swift
let authority = RecordingAuthorityCoordinator(
    store: store,
    transport: transport,
    installation: installationContextStore
)
let state = try await authority.refresh()
let claim = try RecordingAuthorityProposal(
    state: state, action: .claim, deviceID: installation.currentDevice.id,
    buildVersion: .current,
    eventID: .init(rawValue: UUID())
)
try await authority.submit(claim)
```

Keep the proposal until its outcome is known. A retry uses the same event ID;
it returns the original immutable commit even after later transitions. A
conflicting proposal requires a fresh read and user review, not automatic retry.
An approval proposal does not stop hardware: the recording controller must
durably stop before submitting it.

The live transport uses the private custom zone `WhereRecordingAuthority`,
with `WhereAuthorityHead` and `WhereAuthorityEvent` records. Each has a `payload`
Bytes field. The head and immutable event are saved atomically with
`ifServerRecordUnchanged`. Deploy those record types/fields to the production
CloudKit environment before distributing the completed stack. Do not edit or
query SwiftData-generated zones. No public database or external service is used.
A record-zone subscription supplies refresh hints; launch/foreground refreshes
remain required. `LocalRecordingAuthorityTransport` supplies development/demo
state without networking.

`refresh()` resolves the immutable predecessor chain, including recovery choices
missed while offline, then projects commits in one store transaction. Missing
predecessors and conflicting records throw. The projection is operational metadata:
reset and Replace must retain it and backups must not restore its live grants.
`RecordingAuthorityCoordinator` requires the installation sidecar as well as its
store and transport. The first identity verification binds the projection to that
CloudKit account. An account-change notification revokes existing permits and
persists invalidation before retrying. Old responses cannot project authority or
restore access. A different account remains blocked; history and pending commands
stay with the original account. Returning to that account permits a fresh scope.

A cold launch requires identity verification before offline fallback. This also
covers account changes while the process was absent. A temporary outage during an
already verified session retains the existing offline behavior. Missing established
authority never permits another initial claim. Device rejoin preserves the account
binding. These rules are covered by `DataCompatibilityCoordinatorTests` and the
`AccountVerification` model.

### Replacing the recording phone

```swift
// On the new phone: claim an empty account or ask its existing recorder.
let state = try await coordination.selectRecordingRole(.recordingRequested)
// On the existing phone, after explicit approval:
try await services.recording.approveHandoff(requestID: request.requestID)
```

Approval persists an installation-local fence, stops GPS, then commits the
reviewed server transition. `prepareApproval` returns a `PreparedHandoffApproval`
only after writing the fence. `commitStoppedApproval` accepts that type and
rechecks its durable identity and target eligibility. The controller still owns
stopping and draining capture. Uncertain responses reuse the same event ID.
Restart and pending cancellation honor the fence. A cancellation retry retains its event ID.
A verified newer server revision resolves a completed or rejected pending command.
An unchanged head retains the command because a request can still be in flight.
Consent remains local and unchanged on the old phone.
Known removed targets cannot receive approval. A pending request must be cancelled before its target is removed.
An offline established installation uses its last verified authority; malformed
or unauthenticated responses fail closed. Foreground reconciliation refreshes
authority before starting recording. Cloud push refresh is added in the system
integration slice of this stack.

### Lost-phone recovery and backup format 8

When the former phone cannot approve, review its current owner and choose whether
to keep its later automatic observations. The server commit supplies the cutoff.

```swift
try await coordination.recover(
    replacing: reviewedOwner,
    history: .excludeAfterReplacement
)
```

An exclusion applies only to that ownership period at or after the server cutoff.
Raw observations remain stored. Manual entries and earlier ownership grants remain visible.
`SampleRecordingProvenance` distinguishes `.legacy(deviceID:)` from `.owned(Owner)`.
Only the owned case can match a recovery exclusion. A missing provenance value
means no installation attribution. `LocationSample` retains its existing optional
wire fields; backups, outboxes, and SwiftData keep their boundary validation.
An offline former phone stops when it next observes the replacement.

Backup format 8 preserves sample ownership grants, recovery exclusions, and the required
compatibility version. It excludes live authority grants and installation consent.
Merge and Replace retain the greater destination requirement. Unsupported versions
fail before mutation. The external upgrader assigns version 1 to earlier archives.

### Global compatibility and access lifetimes

`DataCompatibilityCoordinator` evaluates one global version before a normal
world opens. The supported version comes from the injected recording coordinator.
Version 1 is the initial contract. Equal versions permit access. A higher shared
version requires an app update. A newer secondary waits for the recording device.
Only that device can advance the server authority, including during background
launch. An offline device can retain an established contract but cannot advance it.

```swift
let state = await compatibility.recheck()
guard case .compatible = state else { return }
let scopedStore = try await compatibility.openDomainStore()
// Assemble the normal world's services with scopedStore.
```

Each scope gets an irrevocable write permit over the existing store. Revocation
rejects new transactions and rolls back suspended transactions before save.
Recovery creates a fresh scope. Ordinary reads can finish during teardown.
`SwiftDataStore` checks current and pending requirements at the transaction commit.
Recovery metadata remains available while the normal session is blocked.

Control-plane inspection and recording coordination remain available while blocked.
The production raw store remains at the bootstrap. `openDomainStore()` returns
`CompatibilityScopedStore`, and `WhereServices.make` requires that concrete type.
Its base and permit are private. Demo composition uses the explicit
`isolatedDomainStore()` SPI, which creates a new memory-only store. Session teardown and
output cleanup use that same lifetime.

`DataCompatibilityState.verificationFailed` and its blocking error carry a
`DataCompatibilityFailure`. Its `error` retains the original typed error and any
underlying cause. Presentation formats the message. Equality identifies one
failure occurrence, so copies remain equal and a new failed check remains observable.

### Retiring a compatibility scope

`WhereServices.suspendForCompatibility()` permanently retires that world's
location source, cancels pending one-shot requests, and stops recording. It
preserves installation consent and accepted outbox entries. Late callbacks
cannot enqueue new samples through a revoked store. Recovery assembles a new
service world with a new store permit.

### System outputs

`WhereServices` retires scope resources. The process-owned `WhereCompatibilityModel`
requests output cleanup through its bootstrap for both blocked startup and scope retirement.
The bootstrap's `DataCompatibilityOutputs` clears notification schedules, badges,
and widget availability, even before the store opens.
Saved notification preferences remain unchanged.

Cleanup does not wait for in-flight publications. Previously started notifications,
widget writes, or Spotlight indexing can finish afterward. This contract prevents
stale store transactions, but does not guarantee immediate removal of every display.

A successful widget snapshot write publishes its supported version.
`CompatibleWidgetSnapshotReader` checks availability once before reading the cache.
Missing or malformed metadata hides cached data. WidgetKit refresh remains asynchronous.

`StandaloneDataCompatibility.requireAccess(to:)` permits a short-lived extension
to write only at the current global version. It never claims recording ownership
or advances the floor. The share extension checks it inside the store transaction.

History observation only checks the local version requirement. It can block access,
but cannot restore access or advance the global version. A sufficient local
requirement preserves the current decision, including waiting and failed states.
Startup, foreground, CloudKit pushes, and explicit user actions request full
verification. Concurrent callers share one verification task. Local imports can
still enforce a higher floor while that task waits.

A blocked device can therefore wait for the next verification trigger after sync
makes its history compatible. Recording-role choices and Retry already request
verification. Account changes still invalidate access before verification of the
original account. Previously verified devices retain the existing offline fallback
for temporary network failures.

The `CompatibilityVerification` model checks these transitions.
`CompatibilityWrites` checks the transaction boundary across lockout and recovery.
