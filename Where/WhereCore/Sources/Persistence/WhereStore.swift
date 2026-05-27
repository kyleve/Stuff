import Foundation

/// Persistence boundary for the Where feature. Everything that crosses
/// this protocol is a value type, so callers (and `WhereController`)
/// never see SwiftData, CoreData, or CloudKit internals.
///
/// All methods are `async throws` so the production CloudKit-backed
/// implementation has somewhere to surface I/O errors.
///
/// All mutating methods (`add(sample:)`, `write(evidence:blob:)`,
/// `setManualDay`, `clear(in:)`, and the `EvidenceBlobStore` writers)
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
    func evidenceBlob(for id: UUID) async throws -> Data?

    /// Set (or replace) the manual presence record for a given calendar day.
    /// Implementations should treat `day.date` as already normalized to the
    /// start-of-day key (callers via `WhereController` do this for them).
    func setManualDay(_ day: DayPresence) async throws
    func manualDays(in interval: DateInterval) async throws -> [DayPresence]

    /// Erase all samples / evidence / manual entries whose timestamp lies in
    /// the given interval. Used by `WhereController.clearYear`.
    func clear(in interval: DateInterval) async throws
}
