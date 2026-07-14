import Foundation
import RegionKit

/// Persistence boundary for the Where feature. Everything that crosses
/// this protocol is a value type, so callers (the `WhereServices` collaborators)
/// never see SwiftData, CoreData, or CloudKit internals.
///
/// All methods are `async throws` so the production CloudKit-backed
/// implementation has somewhere to surface I/O errors.
///
/// All mutating methods (`add(sample:)`, `write(evidence:blob:)`,
/// `setManualDay`, `clearManualDay`, `clear(in:)`, and the
/// `EvidenceBlobStore` writers)
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

    func add(sample: LocationSample) async throws
    func samples(in interval: DateInterval) async throws -> [LocationSample]
    func allSamples() async throws -> [LocationSample]

    func write(evidence: Evidence, blob: Data?) async throws
    func evidence(in interval: DateInterval) async throws -> [Evidence]
    /// Every evidence record in the store, regardless of `capturedAt`. Used
    /// by the whole-database backup export.
    func allEvidence() async throws -> [Evidence]
    func evidenceBlob(for id: UUID) async throws -> Data?

    /// Set (or replace) the manual presence record for a given calendar day.
    /// Implementations should treat `day.date` as already normalized to the
    /// start-of-day key (callers via `DayJournal` do this for them).
    func setManualDay(_ day: DayPresence) async throws
    /// Remove the manual presence record for a given calendar day, if any.
    /// `date` is the start-of-day key (callers via `DayJournal` normalize
    /// it). A no-op when no record exists. Used to undo a relabel/backfill for
    /// a single day without disturbing raw samples.
    func clearManualDay(_ date: Date) async throws
    func manualDays(in interval: DateInterval) async throws -> [DayPresence]
    /// Every manual-day record in the store, regardless of `dateKey`. Used
    /// by the whole-database backup export.
    func allManualDays() async throws -> [DayPresence]

    /// Erase all samples / evidence / manual entries whose timestamp lies in
    /// the given interval. Used by `DayJournal.clearYear`.
    func clear(in interval: DateInterval) async throws

    /// Erase every sample / evidence / manual entry in the store. Used by the
    /// "replace" backup-import strategy to mirror the imported file exactly.
    func clearAll() async throws

    /// Every persisted dismissal key for data-resolution issues. Used by the
    /// scanner to filter out already-dismissed issues (it only needs the keys).
    func dismissedIssueKeys() async throws -> Set<String>

    /// Every persisted dismissal with its original `dismissedAt` timestamp. Used
    /// by the whole-database backup export so a restore round-trips dismissals
    /// verbatim.
    func allDismissedIssues() async throws -> [DismissedIssue]

    /// Persist or remove a dismissed data-resolution issue key. Must run inside
    /// `perform { ... }`. Upserts when `dismissed == true` (stamping the current
    /// date); deletes when false.
    func setIssueDismissed(_ dismissed: Bool, key: String) async throws

    /// Restore a dismissal verbatim, preserving its original `dismissedAt`
    /// instead of stamping "now". Upserts by `key`. Must run inside
    /// `perform { ... }`. Used by backup import.
    func restoreDismissedIssue(_ issue: DismissedIssue) async throws

    /// The user's tracked regions — the set the app loads geometry for and
    /// attributes against. Stored as one row per region (so concurrent
    /// cross-device edits merge rather than clobbering the whole set) and read
    /// as a `Set`; when the user hasn't chosen any yet, this returns
    /// ``WhereStore/defaultTrackedRegions``.
    func trackedRegions() async throws -> Set<Region>

    /// Add (`tracked == true`) or remove (`false`) a single tracked region by
    /// its `Region.rawValue`. Per-region so two devices adding different regions
    /// both survive a sync. Must run inside `perform { ... }`.
    func setTrackedRegion(_ tracked: Bool, id: String) async throws
}

extension WhereStore {
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

    /// Default: a no-op. `SwiftDataStore` overrides this to persist rows; test
    /// fakes that don't exercise tracked-region persistence inherit the no-op.
    public func setTrackedRegion(_: Bool, id _: String) async throws {}
}
