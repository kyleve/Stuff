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

For multi-device history work, read [the design contract](../MULTI_DEVICE_RECORDING.md).
It distinguishes proposed behavior from the current implementation.
That document also owns the implementation plan.

## Scope & dependencies

- Dependencies live in the root [`Package.swift`](../../Package.swift). It
  must **not** import SwiftUI or UIKit. If a behavior would still be correct
  without SwiftUI, it belongs here, not in `WhereUI`.

## Shape & invariants

- Keep the multi-device assessment foundation pure until the [activation gates](../MULTI_DEVICE_RECORDING.md#major-activation-and-rollout) pass.
  Supply complete adjacent evidence before clipping a query. Preserve all equal-timestamp observations.
  Resolve causal decisions through explicit predecessor identities, without timestamp or revision-prefix winners.
  Guards: `MultiDeviceAssessmentTests`, `RecordingTrackAssessmentTests`, and the `MultiDeviceDecisions` model.

- Preserve established UTC offsets with recording calendar context. Do not recompute persisted assignments through the current time-zone database.
  Validate synthesized control values at admission and resolution boundaries. Keep causal predecessors within their device or place scope.
  Guards: `RecordingCalendarContextTests`, `RecordingDayCoverageTests`, and the recording-control resolver tests.

- Use InstallerKit for local and published build identity, feed validation, and cache policy.
  Keep `WherePreferences.installerUpdates` device-local. `BuildInfo` exposes an
  installer identity only for the Development audience.

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
  `SwiftDataStoreTests.readSnapshotRejectsCommitBeforeNotification`. A snapshot
  inside a mutation pins durable history until its pre-save check; concurrent
  commits throw `WhereStoreReadConflictError` before local edits are saved. Each
  committed transaction pings `changes()`. Never expose its `ModelContainer`
  through `WhereServices`. The separate DEBUG Inspector runtime uses
  `SwiftDataStore.makeContainer`, `inspectorModelTypes`, and
  `inspectorStoreURL` as its schema/storage adapter.
- Keep envelope indexes within the owning task's transaction or read snapshot. Pin persistent history before the first cached read.
  Invalidate cached compatibility metadata after ordinary mutations. Keep legacy sample identities current after writes, clears, and generation rotation.
  Recheck compatibility from fresh headers at the physical save. Resolve identity collisions only within the requested generation; admit major headers globally.
  Guards: `VersionedHistoryIndexTests` and `SwiftDataStoreLocationSamplesTests`.
- Keep the compatibility permit around the outermost store transaction.
  Domain collaborators must receive the scoped wrapper, not its raw base.
  Keep physical saves and permit revocation under the same mutex.
  A completed read does not authorize later output publication; retain a separate publication guard.
  Guard: `SwiftDataStoreTests.revokedScopeCannotCommitASuspendedTransaction`.
- Use `WhereStore.dataContractMajor()` for active payload and import/export semantics. A verified account requirement can precede all local metadata.
  Keep `dataCompatibilityState()` limited to actual local headers for admission. Physical GPS reads and writes include the current permit's requirement.
  Recheck newly arrived headers against the permit before decoding samples or controls; decoder support cannot expand admitted access.
  Guards: `CompatibilityScopedStoreTests`, `SwiftDataStoreCompatibilityTests`, `SwiftDataStoreLocationSamplesTests`, and `BackupCoordinatorTests`.
- Compatibility-scoped services serialize asynchronous history output through `DataCompatibilityOutputs`.
  Construct production services with `WhereServices.make(access:...)`; raw-store assembly is preview/demo SPI.
  Await its retirement before replacement services publish. Cancellation does not abandon submitted system calls.
  Join scope-owned physical starts and one-shot requests during retirement. Reject their late results.
  Scope retirement preserves recording consent and the accepted outbox; only a new scope can resume capture.
  Guards: `DataCompatibilityOutputsTests`, `DataCompatibilityOutputQueueTests`, `DeviceRecordingControllerTests`.
- Admit version-envelope headers before payloads. Preserve observed major requirements even
  after stale verification. Keep shared observations in the account-bound, backup-excluded
  cache; never mirror a queued control-floor write across account changes. During shared
  activation, durably invalidate cached grants and block re-admission until the mutation returns.
  Invalidate durable grants before fetching shared requirements. Re-enable them only after
  pending reads drain; a failed high-floor save must not expose an older grant after relaunch.
  Guards: `DataCompatibilityCoordinatorTests`, `CloudKitDataCompatibilityTransportTests`.
- Keep admitted dataset identity immutable on each access. Never relabel an existing scope after an account change or missing sidecar.
  Treat identity as routing metadata, not a write grant. Guard: `DataCompatibilityCoordinatorTests`.
- Keep versioned control scope outside its opaque payload. Validate envelope identity, semantics, scope, and causal family before application.
  Reset and Replace erase outgoing control payloads while preserving their observed major floor.
  Guards: `RecordingControlSnapshotTests`, `RecordingControlCodecTests`, and `RecordingControlStoreTests`.
- Bind reviewed source and control writes to their admitted service, generation, relevant evidence, query, and full policy version.
  Validate caller request scopes before entering admitted reads; invalid input must not revoke history access.
  Preserve operation identity and reviewed predecessors on retry. Require complete calendar coverage for a whole-day choice.
  Review control batches against combined evidence and commit them in one local transaction. Partial remote delivery requires another review.
  Keep opaque controls unresolved after a source choice. Guard: `RecordingChoiceCoordinatorTests` and `RecordingReviewTransactionTests`.
- Shortened ignore edits restore their old tail within the same immutable operation. Preserve the selected end day, zone, and offset.
  Include observed causal extensions in refreshed end-date and resume previews. Keep a resume's original cutoff and elapsed history.
  Bound resumes by ignored portions, excluding a shortened operation's restored tail.
  Never expand an existing proposal during Apply.
  Read ignore history through the admitted coordinator. Retain elapsed intervals, causal uncertainty, and unknown control scopes.
  Inspect the exact ignore proposal through the shared control selector, including source-choice and removal precedence.
  Read historical place definitions through the admitted coordinator. Inspect the exact proposal without filling validity gaps or discarding opaque control scopes.
  Guards: `RecordingPlaceHistoryTests` and `RecordingPlaceInspectionTests`.
  Calendar recovery must preserve known raw assignments. Reject an edit that conflicts with a known offset, including observations received after preview.
  Split explicitly confirmed historical zones at every offset transition. Preserve unconfirmed gaps between periods.
  Guards: `RecordingControlEditCoordinatorTests`, `RecordingIgnoreHistoryTests`, `RecordingIgnoreInspectionTests`, `RecordingIgnoreResolverTests`, and `RecordingCalendarRecoveryTests`.
- Resolve source choices and automatic eligibility through `RecordingControlSelection`.
  Preserve exclusive gaps and removal-affected review periods. An explicit source bypasses ignores, including conflicting or incomplete ignore operations.
  Automatic eligibility uncertainty must remain unresolved when that device's evidence can affect the period.
  Guard: `RecordingControlSelectionTests`.
- Establish shared compatibility before opening a new CloudKit mirror.
  Retain one `DataCompatibilityStorePreparation` and coordinator per dataset; scope replacement must reuse them.
  Treat local file presence as conservative legacy evidence and admit actual headers after opening, before any grant.
  Guard: `DataCompatibilityCoordinatorTests.sharedInitializationPrecedesMirrorCreation`.
- **Resolve destructive generations as a multi-parent causal DAG.** A rotation
  names every real maximal head. Two unjoined reset heads resolve to a
  deterministic empty UUIDv8 synthetic generation until the next rotation joins
  them. Persisted generation events must never use that reserved namespace.
  Retire a profile whose registration frontier omits any observed account-reset
  generation
  (`WhereDataGenerationTests.resetBarrierRejectsEarlierRegistrationAndAcceptsLaterRegistration`).
- **Each process opens its on-disk store once and injects it.** The app's
  retained bootstrap opens it after admission for setup or launch. The App Intents stack shares it via
  `WhereServices.forIntents(sharingStoreOf:)`. A second container over the
  same file is how a fresh install once raced the launch into failure (root
  [Composition](../../AGENTS.md#composition-create-once-inject-down)).
- **On-disk storage always carries an explicit App Group identifier.** Audience
  selection belongs to host targets; WhereCore must not own a production or
  development default.
- **Primary regions *are* the tracked-region set.** `primaryRegions()` /
  `setPrimaryRegions(_:)` read/write the same `SDTrackedRegion` rows as
  `trackedRegions()`. Picking scopes GPS attribution *and* carries each
  region's `RegionAppearance` + pick order. `RegionAppearance` carries the
  persisted `RegionSymbol`. Its mapping to SFSafeSymbols and `Color` is
  presentation (WhereUI).
- **Export backups from one `readSnapshot` and keep restorable user data
  lossless.** Preserve optional motion and every sample-attribution revision,
  including reset tombstones. Add persisted user-data shapes end-to-end and cover both import
  strategies. Export no target-owned recording check-ins. Ignore any in an
  imported archive (`BackupServiceTests` / `BackupCoordinatorTests`).
- Preserve recording-day assignments and versioned controls through both backup strategies.
  Admit the archive's required major before history payloads. Import cannot activate or lower the dataset contract.
  Major-one GPS must have device attribution and an explicit day assignment; missing context stays unresolved.
  Store its complete observation in the existing atomic version envelope, so record-first delivery exposes its required major.
  Keep observation IDs in causal-family validation when excluding their payloads from control snapshots.
  Reject differing raw GPS payloads that reuse an identity. Clearing observations also resets their correction revisions.
  Guards: `BackupServiceTests`, `BackupCoordinatorTests`, and `SwiftDataStoreTests`.
- **Backup import never adopts or changes local recording consent.** Archives
  omit that device-local choice. Replace preserves it and every existing
  removal tombstone while rotating the data generation and discarding the local
  outbox (`BackupCoordinatorTests`).
- Queue shared attachments without opening history. Import only through admitted services, with evidence and its receipt in one generation-guarded transaction.
  Load one draft at a time and acknowledge it after commit. Keep receipts across evidence deletion, Reset, and Replace to prevent retry resurrection.
  Close and join imports before Reset. Reopen only the owning failed reset's prior state; committed resets keep the old importer closed.
  Exclude the pending inbox from system backup and omit delivery receipts from user archives.
  Guards: `SharedEvidenceImporterTests`, `SwiftDataStoreSharedEvidenceTests`, `FileSharedEvidenceDraftQueueTests`.
- **Gate import recovery with a two-phase sidecar plus an atomic store
  receipt.** Never clear a committed onboarding marker before its independent
  terminal completion tombstone
  (`BackupCoordinatorTests` / `WhereLaunchTests`).
- **Keep the backup archive strict synthesized `Codable`.** A shape change
  bumps `BackupArchive.currentFormatVersion` and extends
  [`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb). Never add an
  in-code legacy decode fallback.
- **Resolve planned stays independently by their stable stay identity.** Order revisions by
  `updatedAt` then revision UUID. Delete with a newer nil tombstone. Retain completed plans
  (`PlannedStayCoordinatorTests`).
- **Keep forecast home intent separate from tracked regions and display preferences.** A nil
  home-register revision selects historical estimates. Read both planning registers in one
  `readSnapshot`. Never write plans into recorded presence (`PlannedStayCoordinatorTests`).
- **Validate planning windows at store and backup boundaries.** Use inclusive `CalendarDay`
  endpoints with latest arrival no later than earliest departure. Preserve all revision identities
  and tombstones during backup restore (`BackupServiceTests`, `BackupCoordinatorTests`).
- **Keep planned-stay location checks advisory.** `PlannedStayLocationVerifier` accepts a fix
  inside the region or within the configured drift threshold outside its boundary. Do not add
  horizontal accuracy to the threshold.
- Persist textual day keys through `CalendarDay.iso8601`, never its diagnostic `description`.
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
  or removal history, and incomplete raw observations, throw and fail closed instead of dropping into a benign
  state. The one-time reshape path is backup **export → transform
  ([`../Tools/upgrade-backup.rb`](../Tools/upgrade-backup.rb)) →
  replace-import**. Deliberate pre-release. The durable successor
  (per-entity schema versioning) is filed in [`../TODOs.md`](../TODOs.md).
- **Writes await their side effects.** `DayJournal` commits. Then it awaits
  the reminder reconcile + widget publish in sequence. A reader on the next
  `changes()` ping never observes a half-applied write.
- **Observe remote history through Where's `ModelContainer` and exclude this
  store instance's transaction author.** Never let Periscope or Where's own
  local saves enter `remoteChanges()`. Guard: `StoreRemoteChangeSourceTests`.
- **Route new writes through the existing reconciliation seams.** Use
  `DayJournal.reconcileAfterDayDataChange()` or `reconcileIssueState()`.
  Do not copy the incomplete `setPrimaryRegions` or summary fan-out paths
  tracked in [`../TODOs.md`](../TODOs.md).
- Follow the scoped [data-resolution rules](Sources/DataResolution/AGENTS.md)
  for GPS reviews, sample corrections, and scan publication.
- **Use `LocationHistoryReader.projection` for every user-facing location read.**
  Apply removal cutoffs before correction revisions. Reports, maps, artwork,
  widgets, summaries, reminders, and intents use effective attribution; trajectory
  assessment and review retain raw observations. Pin live attribution to the
  tracked set in the same store snapshot.
- **Read related year projections from one samples snapshot.** Use
  `ReportReader.yearReportDetails(for:)` for the scene's report, configured
  primary set, primary-region locations, and Elsewhere evidence.
- **Elsewhere is a read-only projection.** `ElsewhereResolver` expands ordinary
  Other coordinates against the catalog on its actor. Preserve explicit sample
  corrections and manual assertions. Never write inferred names back to reports,
  calendars, or widget totals. Load full-catalog geometry only on demand.
- **`LocationSource` abstracts GPS.** `CoreLocationSource` runs in production.
  `ScriptedLocationSource` runs in tests/previews. `requestCurrentLocation()`
  returns a typed, nonthrowing outcome and coalesces concurrent waiters without
  coupling their cancellation. Reject negative accuracy everywhere. Apply the
  1 km, 60-second, and boundary-confidence gates only in
  `CurrentRegionResolver`; retain other valid passive samples. It backs
  `LocationIngestor.captureTodayIfNeeded(now:)`. Keep the one-shot system
  controls behind `CurrentLocationRequestDriving`, with a conforming fake in
  `CoreLocationSourceTests`. Keep coalesced waiters and their timeout in one
  idle/pending request state; finish each waiter exactly once.
- **`DeviceRecordingController` owns this installation's local recording choice
  and physical GPS state.** Serialize mutations across awaits. Fail closed when
  the current identity is removed. Stamp every ingested GPS sample with the
  current installation id. Apply `LocationHistoryReader` to every user-facing
  projection. Persist immutable profiles, nickname events, global removal
  tombstones, and target-owned advisory check-ins separately. A remote device
  may rename or remove an identity. It must never change another installation's
  local consent. Backups alone read lossless raw samples and device/removal
  timelines, excluding non-restorable check-ins.
- Keep historical device-name lookups inclusive of removed profiles.
  Use the latest saved nickname or the profile's hardware name.
- Keep recording identity in a nonsynchronizing `AfterFirstUnlockThisDeviceOnly` Keychain item.
  Only `errSecItemNotFound` means absence. Rotate with an expected-identity check.
  Keep consent outside Keychain and require renewed consent when its sidecar is absent.
  Guards: `KeychainRecordingIdentityStoreTests`, `RecordingIdentityRecoveryPolicyTests`.
- Preserve an import recovery marker's original `installationID` through identity changes.
  Query and delete its receipt with that owner. Guard: `BackupCoordinatorTests.preparedImportKeepsItsOriginalReceiptOwnerAfterIdentityReplacement`.
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
- Keep calendar zoom choices device-local and outside backup archives. Use stable `CalendarZoomKey` namespaces and clear all of them through `WherePreferences.reset()`. Guards: `CalendarZoomKeyTests`, `WherePreferencesTests`.
- Keep welcome history in one encoded preference. Distinguish missing history from an explicit reset with no saved region.
  Keep it outside backup archives. Guard: `WherePreferencesTests`.
- **Keep diagnostic reporting intent in one encoded composite preference.** Keep crash,
  replay, remote threshold, and export policy vendor-neutral. Invalid stored
  values assert in Debug and resolve remote logging Off. Reset removes every reporting key.
- **`WhereTheme` is device-local preference state, not backup/domain data.**
  Preserve its stable raw values. Make unknown or missing values Standard. Publish it through
  `WidgetPresentationPublisher`. Never put it in `WidgetSnapshot`. Never rebuild widget data for a
  presentation-only change.
- **`DemoDataBuilder` seeds through the ordinary write paths** (`DayJournal`,
  `setPrimaryRegions`). No private door into the store. A demo exercises
  the code a real user does. Its data is sized against the *elapsed* year, not
  the calendar. Configured issue categories must be independently selectable:
  checked categories appear and unchecked categories do not. Keep any
  early-year clock adjustment inside the in-memory demo. Guard:
  `DemoDataBuilderTests.holdsItsShapeWhereverInTheYearItIsEntered`.
- **Impossible states trap. Recoverable ones surface.** `WhereStore` methods
  are `async throws`. A `catch` logs a typed `WhereLog` event (PII-free,
  `.public`) and leaves state honest. When the event accepts `LogError`, pass
  the original error through `.restricted(.errorDetails, error)`. Do not add
  a duplicate error attachment. Follow PeriscopeCore's structured-error contract.
  Never use a benign-looking default. The `WhereLog` facade and every
  `*Log.swift` event type live together in `Sources/Logging/`.
- **Expensive Core work is spanned, with a budget.** That includes bulk reads
  and `perform` commits, aggregation, calendar layout, issue detection, the
  reconcile fan-out, backup, GPS acquisition. Names come from each `*Log`'s
  nested `SpanName`. See [Spans](../AGENTS.md#spans) for the convention. A
  detector names its own span through `DataIssueDetecting.detects`.
  `DataIssueScanner` measures detector passes with `detect(category)` and the
  shared flight/boundary assessment with `assessGPS`; see `DataIssueScannerLog`.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in
`StuffTestHost`. Drive collaborators against `SwiftDataStore.inMemory()` +
`ScriptedLocationSource`. Never use the user's on-disk/CloudKit store or live
Core Location requests. Keep production-source history tests in isolated
temporary on-disk containers without CloudKit (`StoreRemoteChangeSourceTests`).
`CoreLocationSourceTests` must replace the source’s
one-shot controls with a `CurrentLocationRequestDriving` fake before requesting
a fix; never start passive monitoring in those tests. The CloudKit remote-import path uses the
`@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`.

Keep raw flight archives and export configurations outside Git. Preserve the complete selected GPS window before minimizing a regression.
Verify transformation fidelity with `FlightFixtureExporterTests` and write expected flight behavior independently of detector output.
Require explicit `coordinateMode: preserve` to export original coordinates. Keep coordinate provenance in the JSON fixture's `coordinates` field.
Keep recorded windows in `Tests/Fixtures/Flights/` as `RecordedFlightFixture` JSON. Load them from the test bundle and keep expected behavior in Swift tests.
The [recorded-fixture procedure](README.md#recorded-flight-fixtures) covers extraction and publication.

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
