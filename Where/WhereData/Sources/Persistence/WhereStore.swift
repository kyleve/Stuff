import Foundation
import WhereCore

/// Persistence boundary for `WhereData`. Everything that crosses this protocol
/// is a `WhereCore` value type, so callers (and `WhereController`) never see
/// SwiftData, CoreData, or CloudKit internals.
///
/// All methods are `async throws` so the production CloudKit-backed
/// implementation has somewhere to surface I/O errors.
public protocol WhereStore: Sendable {
    func addSample(_ sample: LocationSample) async throws
    func samples(in interval: DateInterval) async throws -> [LocationSample]
    func allSamples() async throws -> [LocationSample]

    func addEvidence(_ evidence: Evidence, blob: Data?) async throws
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
