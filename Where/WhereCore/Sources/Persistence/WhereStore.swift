import Foundation

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

    /// Every persisted dismissal key for data-resolution issues.
    func dismissedIssueKeys() async throws -> Set<String>

    /// Persist or remove a dismissed data-resolution issue key. Must run inside
    /// `perform { ... }`. Upserts when `dismissed == true`; deletes when false.
    func setIssueDismissed(_ dismissed: Bool, key: String) async throws
}
