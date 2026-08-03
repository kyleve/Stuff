import Foundation
import RegionKit

/// Persistence boundary for the Where feature. Everything that crosses
/// this protocol is a value type, so callers (the `WhereServices` collaborators)
/// never see SwiftData, CoreData, or CloudKit internals.
///
/// All methods are `async throws` so the production CloudKit-backed
/// implementation has somewhere to surface I/O errors.
///
/// All mutating methods (`add(sample:)`, recording profile/metadata/check-in/event writes,
/// `write(evidence:blob:)`, `setManualDay`,
/// `clearManualDay`, `clear(in:)`, and the `EvidenceBlobStore` writers)
/// MUST be called from inside a `perform { ... }` block — the block
/// boundary is what owns the underlying write transaction. The
/// production `SwiftDataStore` implementation traps with a
/// `preconditionFailure` if a mutation is called outside `perform`.
public protocol WhereStore: Sendable {
    /// Run `block` inside a write transaction. On outermost success
    /// the staged writes are committed atomically; on outermost throw
    /// the entire transaction is rolled back (no partial writes
    /// reach the persistent store). Nested `perform` calls are
    /// coalesced into the in-flight transaction so callers can
    /// freely compose store operations without doubling up on I/O
    /// or fragmenting atomicity.
    @discardableResult
    func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T

    /// Run a mutation only if the account is still in `expectedDataEpochID`. Callers capture the
    /// epoch before any suspension that informs the write; a reset/Replace crossing that work
    /// then fails instead of admitting a stale decision into the new generation.
    @discardableResult
    func perform<T: Sendable>(
        expectedDataEpochID: WhereDataEpochID,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T

    /// Pin every read in `block` to one logical data epoch and verify that epoch and the durable
    /// store generation are still current before returning. This is the multi-table read boundary
    /// for policy decisions and backup export; a remote commit crossing its reads invalidates the
    /// result through persistent history even if its notification has not arrived yet.
    @discardableResult
    func readSnapshot<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T

    /// A fresh stream that emits whenever committed data changes — once after
    /// every outermost `perform` transaction commits, and (for a CloudKit-backed
    /// store) on a remote import synced from another device. The payload is a
    /// bare `Void`: subscribers re-read what they care about, so they only need
    /// to know *that* something changed, not what. Each call returns its own
    /// independent stream that drops out of the fan-out when iteration stops.
    ///
    /// This is the single read-refresh signal: every write origin (manual edit,
    /// live GPS ingestion, remote sync) funnels through `perform` or the remote
    /// import, so a consumer that re-derives on each ping can't go stale.
    func changes() -> AsyncStream<Void>

    /// Remote-import subset of ``changes()``. On-disk implementations emit only when another
    /// process or CloudKit changes the store; local `perform` commits do not. Headless derived
    /// outputs subscribe here so remote data refreshes them without duplicating the synchronous
    /// reconciliation local writers already await.
    func remoteChanges() -> AsyncStream<Void>

    /// Current account-wide logical generation. Rows from older epochs are retained only as
    /// sync/audit history and never participate in normal reads.
    func dataEpoch() async throws -> WhereDataEpoch

    /// Atomically erase the active epoch's synced rows and append a fresh destructive epoch.
    /// Every subsequent write in the same transaction is stamped into the returned epoch.
    /// Immutable device profiles remain global so a late/offline installation can still be
    /// identified, but its old policy and user-data rows cannot affect the new generation.
    func rotateDataEpoch(
        reason: WhereDataEpochReason,
        changedBy deviceID: RecordingDeviceID,
        at date: Date,
    ) async throws -> WhereDataEpoch

    /// Receipt inserted atomically with an import's rows. Lookup is by both the random token and
    /// local installation identity; callers inspect the stamped epoch but treat a receipt in a
    /// superseded epoch as proof that the physical save occurred.
    func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt?

    /// Insert an immutable import receipt. Must run inside `perform { ... }`.
    func addBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws

    /// Remove an import receipt after its device-local recovery marker is durably committed.
    /// Must run inside `perform { ... }`.
    func removeBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws

    func add(sample: LocationSample) async throws
    func samples(in interval: DateInterval) async throws -> [LocationSample]
    func allSamples() async throws -> [LocationSample]

    /// Every assembled synced device read model, including archived devices.
    func recordingDevices() async throws -> [RecordingDevice]

    /// Immutable installation profiles.
    func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile]

    /// Insert a profile, accepting an identical retry and rejecting conflicting contents for
    /// an existing installation id. Must run inside `perform { ... }`.
    func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws

    /// Full append-only nickname timeline. Effective archive authority lives in
    /// ``recordingPolicyChanges()``.
    func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange]

    /// Insert an immutable metadata event. Must run inside `perform { ... }`.
    func addRecordingDeviceMetadataChange(_ change: RecordingDeviceMetadataChange) async throws

    /// Latest target-owned check-in for each installation.
    func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn]

    /// Upsert one target-owned check-in, preserving a newer existing value during backup merge.
    /// Must run inside `perform { ... }`.
    func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws

    /// Every append-only recording-policy event, oldest first.
    func recordingPolicyChanges() async throws -> [RecordingPolicyChange]

    /// Insert one immutable policy event naming every causal head its command observed. An
    /// identical retry is idempotent; a different value with the same id throws. Must run inside
    /// `perform { ... }`.
    func addRecordingPolicyChange(_ change: RecordingPolicyChange) async throws

    /// Complete account-wide automatic-recording assignment history for the active epoch.
    func recordingAssignmentChanges() async throws -> [RecordingAssignmentChange]

    /// Insert one immutable global assignment command. Must run inside `perform { ... }`.
    func addRecordingAssignmentChange(_ change: RecordingAssignmentChange) async throws

    /// Irreversible device tombstones in the active epoch.
    func recordingDeviceArchives() async throws -> [RecordingDeviceArchive]

    /// Insert an immutable archive tombstone. Must run inside `perform { ... }`.
    func addRecordingDeviceArchive(_ archive: RecordingDeviceArchive) async throws

    func write(evidence: Evidence, blob: Data?) async throws
    func evidence(in interval: DateInterval) async throws -> [Evidence]
    /// Every evidence record in the store, regardless of `capturedAt`. Used
    /// by the whole-database backup export.
    func allEvidence() async throws -> [Evidence]
    func evidenceBlob(for id: UUID) async throws -> Data?

    /// Set (or replace) the manual presence record for a calendar day, keyed by
    /// `day.day` (its timezone-independent `CalendarDay`).
    func setManualDay(_ day: DayPresence) async throws
    /// Remove the manual presence record for `day`, if any. A no-op when no
    /// record exists. Used to undo a relabel/backfill for a single day without
    /// disturbing raw samples.
    func clearManualDay(_ day: CalendarDay) async throws
    /// The manual-day records whose `CalendarDay` falls in the inclusive
    /// `dayRange`. Used to load a year's manual entries.
    func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence]
    /// Every manual-day record in the store, regardless of day. Used by the
    /// whole-database backup export.
    func allManualDays() async throws -> [DayPresence]

    /// Erase samples / evidence whose timestamp lies in `interval` and manual
    /// entries whose `CalendarDay` falls in `manualDays`. Manual days key by
    /// calendar day (not instant), so they take a `CalendarDay` range rather
    /// than the timestamp interval used for samples/evidence. Used by
    /// `DayJournal.clearYear`.
    func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws

    /// Every persisted dismissed data-resolution issue id. Used by the scanner
    /// to filter out already-dismissed issues (it only needs the ids).
    func dismissedIssueIDs() async throws -> Set<DataIssueID>

    /// Every persisted dismissal with its original `dismissedAt` timestamp. Used
    /// by the whole-database backup export so a restore round-trips dismissals
    /// verbatim.
    func allDismissedIssues() async throws -> [DismissedIssue]

    /// Persist or remove a dismissed data-resolution issue. Must run inside
    /// `perform { ... }`. Upserts when `dismissed == true` (stamping the current
    /// date); deletes when false.
    func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws

    /// Restore a dismissal verbatim, preserving its original `dismissedAt`
    /// instead of stamping "now". Upserts by id. Must run inside
    /// `perform { ... }`. Used by backup import.
    func restoreDismissedIssue(_ issue: DismissedIssue) async throws

    /// The user's tracked regions — the set the app loads geometry for and
    /// attributes against. Stored as one row per region (so concurrent
    /// cross-device edits merge rather than clobbering the whole set) and read
    /// as a `Set`; when the user hasn't chosen any yet, this returns
    /// ``WhereStore/defaultTrackedRegions``.
    func trackedRegions() async throws -> Set<Region>

    /// The user's tracked regions with their picked appearance and pick order —
    /// the same rows ``trackedRegions()`` reads, surfaced as ordered
    /// ``PrimaryRegion`` values for the picker/customization UI. Ordered by the
    /// stored pick order (rows without one sort last, then by region id). When
    /// the user hasn't chosen any yet, mirrors ``WhereStore/defaultTrackedRegions``
    /// (in canonical order, with no stored appearance).
    func primaryRegions() async throws -> [PrimaryRegion]

    /// Add (`tracked == true`) or remove (`false`) a single tracked region by
    /// its `Region.rawValue`. Per-region so two devices adding different regions
    /// both survive a sync. Must run inside `perform { ... }`.
    func setTrackedRegion(_ tracked: Bool, id: String) async throws

    /// Replace the entire primary set with `regions`: upsert a row per entry
    /// (storing its `appearance` — cleared when `nil` — and pick `order`) and
    /// delete every tracked row not in `regions`. The picker/customization
    /// commit path — the ordered list fully describes the primary (tracked) set,
    /// so removals happen by omission rather than a separate call. Must run
    /// inside `perform { ... }`.
    func setPrimaryRegions(_ regions: [PrimaryRegion]) async throws
}

extension WhereStore {
    public func perform<T: Sendable>(
        expectedDataEpochID: WhereDataEpochID,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await perform {
            guard try await (dataEpoch()).id == expectedDataEpochID else {
                throw RecordingPersistenceError.dataEpochChanged
            }
            return try await block()
        }
    }

    public func readSnapshot<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        let expected = try await (dataEpoch()).id
        let result = try await block()
        guard try await (dataEpoch()).id == expected else {
            throw RecordingPersistenceError.dataEpochChanged
        }
        return result
    }

    /// Stores without an external writer never emit remote changes.
    public func remoteChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    /// Regions tracked out of the box, until the user chooses their own. The
    /// "no rows yet" fallback for ``trackedRegions()`` and the historical
    /// California / New York / Canada / European Union set.
    public static var defaultTrackedRegions: Set<Region> {
        [.california, .newYork, .canada, .europeanUnion]
    }

    /// Default: the out-of-the-box set. `SwiftDataStore` overrides this with the
    /// persisted rows; in-memory test fakes inherit the default.
    public func trackedRegions() async throws -> Set<Region> {
        Self.defaultTrackedRegions
    }

    /// Default: derive ordered primary regions from ``trackedRegions()`` with no
    /// stored appearance. `SwiftDataStore` overrides this to read the persisted
    /// appearance and pick order; test fakes inherit this catalog-ordered view.
    public func primaryRegions() async throws -> [PrimaryRegion] {
        try await Region.inCanonicalOrder(trackedRegions())
            .enumerated()
            .map { PrimaryRegion(region: $1, appearance: nil, order: $0) }
    }

    /// Default: a no-op. `SwiftDataStore` overrides this to persist rows; test
    /// fakes that don't exercise tracked-region persistence inherit the no-op.
    public func setTrackedRegion(_: Bool, id _: String) async throws {}

    /// Default: a no-op. `SwiftDataStore` overrides this to replace the persisted
    /// rows; test fakes that don't exercise persistence inherit the no-op.
    public func setPrimaryRegions(_: [PrimaryRegion]) async throws {}
}
