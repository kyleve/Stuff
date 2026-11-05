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

The [multi-device recording design](../MULTI_DEVICE_RECORDING.md) defines the proposed
history-selection model and its implementation plan.
The pure assessment foundation exists below. Production history still uses the existing removal and correction rules.

## Multi-device assessment foundation

`MultiDeviceAssessment.assess(observations:within:places:)` compares separate device tracks without store access or mutations.
Validated observations require GPS device attribution and explicit recording-day context, or an unresolved assignment.
Region inputs come from the full catalog, with effective corrections applied by the caller.
Results retain uncertainty, supporting evidence, and the full policy version.
The [primary design](../MULTI_DEVICE_RECORDING.md#initial-assessment-policy) defines interval and evidence semantics.

`RecordingDayCoverage.resolve(day:within:contexts:)` derives a logical day's possibly disjoint periods from calendar-context coverage.
`searchPeriod(for:)` supplies a complete search bound for all supported UTC offsets.
Missing context produces a clarification requirement.

`HistoryDecisionResolver.resolve(_:within:version:)` resolves immutable decisions with explicit predecessor identities.
Concurrent incompatible decisions and missing dependencies remain visible per period.
The [decision model](../Specifications/MultiDeviceDecisions/README.md) describes the bounded proof and source correspondence.
These pure APIs do not activate history selection.
The remaining integration and activation requirements stay in the primary design.

## Durable recording-control values

Source choices, ignore edits, place edits, and calendar-context edits carry typed UUID identities and explicit predecessor sets.
Their pure resolvers share `CausalPeriodResolver`, which preserves concurrent conflicts and missing dependencies within each affected period.
Place and calendar edits cannot replace another place's or device's operations.
An ignore expiry does not erase its historical interval. Resume changes future eligibility, while undo changes the reviewed elapsed interval.
Concurrent ignores agree where both exclude a device, even when their end dates differ.
Changing an ignore's end claims its old and new coverage in one operation.
After a shortened end, that operation restores eligibility on the old tail. Its saved day and zone remain available for inspection.
If another edit extends the ignore, the refreshed preview includes that extension. Saving the larger scope requires another confirmation.
`RecordingControlEdit.resumingIgnore(_:at:)` uses the same refresh rule and retains the explicit resume cutoff.
It restores only the reviewed future interval. Undoing elapsed history remains a separate bounded eligibility edit.

`RecordingCalendarContext` retains both the original zone name and its established UTC offset.
`RecordingDayAssignment` and `RecordingDayCoverage` use the saved offset, without reinterpreting history through the current zone database.
Coverage splits at offset changes, including daylight-saving transitions.
Synthesized `Codable` preserves the strict wire shape. Admission and resolver boundaries validate decoded dates, periods, coordinates, and offsets before use.

`RecordingControlStore` reads these values through admitted version envelopes in a pinned store snapshot.
The envelope retains the affected scope separately from its payload. Unknown meaning remains available for review, with its original bytes intact.
Canonical predecessor order makes restored retries byte-identical. Reusing an identity for different content fails the transaction.
Reset and Replace erase outgoing control payloads while retaining the highest observed compatibility requirement.

`LocationSample.recordingDay` preserves resolved or explicitly unresolved observation context through storage and backups.
Raw sensor measurements and foundation-era rows may omit it. Major-one admission requires both device attribution and an explicit assignment.
Incomplete raw rows fail reads instead of disappearing from an apparently complete history.
Major-one GPS uses the existing atomic version envelope. Its required major remains visible when an observation arrives before shared compatibility metadata.
Control snapshots validate observation identities and causal references, then expose only controls.
Identical observation deliveries coalesce. Conflicting raw payloads cannot replace provenance through Merge.

Backup format 8 preserves controls and recording-day context. Its required major is admitted before decoding history.
The offline converter accepts explicit historical device and calendar mappings; [backup format](BACKUP_FORMAT.md#convert-historical-gps) describes the procedure.
Capture-time context and the controls UI remain in the implementation plan.

`RecordingChoiceCoordinator.review(_:)` prepares a source choice against one relevant history snapshot.
It validates the requested scope before entering that snapshot, so invalid caller input cannot revoke admitted history access.
The proposal keeps the query, evidence, policy version, and original causal predecessors until save completes.
`apply(_:)` reassesses inside the guarded transaction, then appends that immutable operation.
Relevant changes return a refreshed review. Unrelated imports can retry the same proposal without another confirmation.
Proposals cannot cross admitted service instances, even when two accounts share the implicit initial data generation.
An identical committed operation completes a retry without adopting later decisions.
Whole-day proposals require complete calendar context; missing GPS alone does not prevent their exclusive coverage.
The [reviewed-choice model](../Specifications/ReviewedRecordingChoices/README.md) documents the bounded verification and external-writer limitations.
`RecordingControlEditCoordinator` uses the same guarded transaction for ignore, place, and calendar edits.
It also validates caller scopes before entering admitted history reads.
`ignoreHistory(for:)` reads one device's durable ignore graph, including elapsed and unresolved intervals.
Its segments describe automatic eligibility. Explicit source choices can still select that device, and unknown controls remain separately visible.
`inspectIgnore(_:)` compares the exact proposal with its reviewed controls through `RecordingControlSelection`.
The preview preserves source choices, removal cutoffs, unknown controls, and gaps between reviewed periods. It does not read newer evidence or authorize saving.
`placeHistory()` reads precise place definitions by identity, including their earlier validity periods, removals, and unresolved edits.
`inspectPlace(_:)` compares the exact reviewed definition before and after a place edit. Disjoint periods retain their gaps.
These values preserve unknown control scopes separately. Place edits do not resolve those controls or claim changes to GPS presence or report totals.
Its array overload reviews disjoint edits against one combined snapshot. A proposal pairs each edit with its immutable control.
One local transaction saves the complete batch. A retry retains all operation identities and rejects conflicting reused identities.
Remote delivery remains independent for each envelope. A partial batch requires another review before a retry can save its remaining edits.
Calendar recovery can resolve unknown assignments, but cannot override a recorded day or UTC offset.
A conflicting observation received after preview rejects the edit before save and requires the user to revise it.
`RecordingCalendarRecovery` splits explicitly confirmed historical zones into fixed-offset segments, including daylight-saving and political offset changes.
Its `edits` retain the requested periods without filling gaps. Each segment preserves its original zone and established offset.
The resolver applies these controls separately from raw observations. A missing segment remains unresolved until its control arrives.

```swift
// The user confirms this device, exact periods, and historical zone.
let recovery = try RecordingCalendarRecovery(
    deviceID: deviceID, periods: periods, timeZone: confirmedZone
)
let proposal = try await services.recordingControlEdits.review(recovery.edits)
// Present proposal.edits and its evidence before the user chooses Save.
let result = try await services.recordingControlEdits.apply(proposal)
// A stale result requires another review before applying its new proposal.
```

`WhereServices` supplies both coordinators from its admitted store and awaits reconciliation after each successful save.
These APIs require the activated recording contract. The current foundation policy blocks them. Slice 6 owns their user-facing controls.

`RecordingControlSelection` combines source choices, historical ignores, and device removals for each period.
Explicit sources bypass ignores. Removal leaves the selected source exclusive and marks its affected portion unresolved.
Automatic periods retain each device's eligibility, including conflicting or missing ignore decisions.
Consumers must preserve that uncertainty when the device's evidence can affect history. They must not fill an explicit source's gaps.
Unknown controls remain unresolved within their stored scope.
The [control-selection model](../Specifications/RecordingControlSelection/README.md) documents the bounded delivery-order checks.

## Compatibility protocol foundation

`CompatibilityScopedStore` binds reads and transactions to one `DataAccessPermit`.
Revocation is permanent. A fresh scope requires a fresh permit.
`WhereStore.dataContractMajor()` includes the admitted account requirement, even before its first local history record arrives.
`dataCompatibilityState()` retains the actual local headers used for admission. Reading the active contract does not create requirement records.
First GPS writes use atomic version envelopes under the admitted contract; backups use that same contract for export and import validation.
Payload reads recheck the permit at decoding. Versioned-record reads admit and decode the same envelope index.
Malformed admission or observation data retires the scope and surfaces the original error.
`SwiftDataStore` holds the permit's mutex through the physical save, so retirement cannot cross that save's admission check.
Calls suspended during retirement reject their result or staged transaction.
A save that wins before retirement remains durable, even if its caller later receives a revoked-access error.

The scoped store must own the outermost transaction.
Wrapping only a nested operation cannot guard a raw outer transaction.
Returned values and external outputs still need publication guards in their owning services.
The [bounded write model](../Specifications/CompatibilityWrites/README.md) documents these limits and the Swift regression guards.

`DataCompatibilityCoordinator` separates local datasets from shared accounts.
Each `DataCompatibilityAccess.identity` captures its admitted store and, for shared data, account identity.
This immutable metadata does not grant access. Validate the current permit before using it for publication or notification routing.
The composition root adds its configured CloudKit container when binding a local sidecar.
An account change revokes existing access even if its verification cache disappeared during the process.
Local initialization uses a guarded store transaction. Shared initialization verifies the account and private zone inventory, then conditionally creates one control head.
Any existing non-control custom zone is conservatively legacy, even if empty.
`CloudKitDataCompatibilityTransport` uses a separate control zone and conditional change-tag saves.
Its injected database boundary lets tests exercise the production protocol with delayed, failed, and reordered responses.

`DataCompatibilityStorePreparation` retains and coalesces the dataset's physical store open.
Pass it to the coordinator before creating a new CloudKit mirror.
Shared verification and guarded head initialization precede the open, so the new mirror cannot establish its own legacy classification.
An existing local file is conservative legacy evidence. It never establishes account newness or grants access.
After opening, the coordinator admits actual headers before saving a verified cache or granting a scope.
Cancelled waiters cannot abandon the shared open. Failed opens can retry without losing the existing-history classification.
The already-open `init(store:source:policy:activationReadiness:)` remains available for isolated fixtures and existing-store adapters.

The backup-excluded `FileDataCompatibilityCache` binds verification to the account and store.
Network refresh failures can retain same-binding access without a time expiry.
Before fetching shared requirements, invalidate the durable grant and retain the current process's verified proof.
Only completed verification attempts can restore the durable grant. An interrupted check requires fresh verification after relaunch.
This closes the crash window when saving a higher requirement fails.
Account uncertainty, incompatible headers, and revoked permits block access.
Major activation requires contributor eligibility or explicit confirmation, durable grant invalidation, and online server confirmation.
A lost response requires fresh verification. A competing refresh cannot restore the old grant during the mutation.

`VersionedHistoryRecord` stores the version and payload in one field.
Readers decode the major header before interpreting the payload, including records received before metadata.
The scoped store cannot raise the required major or author above its admitted major.
The physical save repeats admission, so a compatible higher-major import also retires an older scope.

See the [verification](../Specifications/CompatibilityVerification/README.md) and [activation](../Specifications/CompatibilityActivation/README.md) models for bounds and source correspondence.
`DataCompatibilityOutputs` wraps notification schedulers and widget publication in one serial queue.
Retirement drains submitted calls, removes owned output, and clears the history badge.
Caller cancellation does not abandon a submitted system call.
Replacement services must await retirement before publishing. Repeated retirement cannot remove replacement output.
Widget file writes also validate access under the permit's physical-write lock.
The [output model](../Specifications/CompatibilityOutputs/README.md) checks the bounded withdrawal ordering.

Recording retirement is permanent for the old controller and ingestor.
It joins a pending physical start before the final stop and preserves accepted retry data.
Stale rollback and destructive cleanup calls cannot resume capture or clear that data.
A fresh compatible scope restores its generation-matching outbox before accepting new samples.

Production assembles `WhereServices.make(access:...)` with an admitted store, guarded output, and a scope-owned location source.
`retireCompatibilityScope()` drains output, stops reconciliation, and joins capture retirement before a replacement starts.
It also rejects late one-shot location results. Preview and demo assembly remain separate SPI entry points.
The app retains one dataset coordinator across service scopes. Its launch gate works without a foreground scene.
The remaining rollout requirements stay in [implementation slice 3](../MULTI_DEVICE_RECORDING.md#3-compatibility-gate).
The foundation does not activate new history selection or write incompatible user data.

### Pending shared evidence

`FileSharedEvidenceDraftQueue` stores immutable metadata and attachment bytes in the App Group without opening history.
Each draft has its own atomic file. Concurrent share processes cannot replace another draft.
The pending directory is excluded from system backup.

Admitted services expose `SharedEvidenceImporter`. It imports a complete draft and its delivery receipt in one guarded transaction.
It loads one draft at a time and removes it only after commit. A retry checks the receipt before writing evidence again.
Reset closes new imports and joins current work before erasure. A failed erase restores prior admission; committed erasure keeps the old importer closed.
Receipts survive evidence deletion, Reset, and Replace, so interrupted acknowledgement cannot restore deleted data.
These delivery receipts are omitted from user backups, like the local pending inbox.
Import errors preserve the queued bytes and remain visible to the caller.

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
  Versioned envelopes share an index within that task's transaction or read snapshot.
  Bulk observation imports decode each existing envelope once instead of scanning history for every insertion.
  Each operation also indexes legacy sample identities and caches compatibility metadata until an ordinary mutation changes it.
  Cached reads pin persistent history, and physical saves still inspect fresh compatibility headers.
  Late conflicting identities in an erased generation remain inert; their major requirements remain global.
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
  in the app, the retained bootstrap opens it after compatibility admission and the App Intents
  stack shares its admitted services via `WhereServices.forIntents(sharingStoreOf:)` — so two
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
  recording-day context, versioned controls, and every sample-attribution revision. Merge preserves revision IDs and timestamps.
  Replace restores revisions into its new generation.
  The offline [`upgrade-backup.rb`](../Tools/upgrade-backup.rb) command upgrades earlier archives.
  Legacy stay revisions retain one shared identity, including deletion tombstones.
  The converter infers arrival from each revision's UTC date, capped at its final day.
  The production decoder accepts only the current format. See [backup format](BACKUP_FORMAT.md).
  Export before upgrading the app. Upgrade the archive offline, then replace-import it.
  Update every syncing installation before editing plans. Older builds use a single
  stay register and can delete independent stays in the shared store.
- **`InstallationRecordingContext`** — the device-local installation identity,
  explicitly confirmed local recording choice, and stable timestamp for recreating
  its immutable device profile idempotently.
  `InstallationRecordingContextStoring` keeps the persistence adapter outside
  the domain value. `KeychainRecordingIdentityStore` keeps its identity and registration
  time in a nonsynchronizing device-only item. `RecordingIdentityRecoveryPolicy` reconciles
  that item with the consent sidecar. Missing consent requires confirmation again;
  unavailable storage never creates a replacement identity. Reset and rejoin rotate deliberately.
  `ImportRecoveryDetails.installationID` retains the original receipt owner through these changes.
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
let services = try await WhereServices.make(
    store: try SwiftDataStore.make(storage: .cloudKit(
        appGroupIdentifier: "group.com.stuff.where"
    )),
    locationSource: CoreLocationSource(),
    installationContext: installationContext, // resolved once by the app composition root
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
  Apple Lost Mode or remote erase remains the security boundary for a missing device. Account
  Reset also retires an installation registered before its causal reset boundary, even when that
  installation's profile did not reach the resetting device until later.
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
