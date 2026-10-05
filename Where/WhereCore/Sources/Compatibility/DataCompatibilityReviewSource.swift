/// Read-only feature preflight. An available review does not authorize a write;
/// activation must still recheck through the compatibility coordinator's transaction.
public protocol DataCompatibilityReviewSource: Sendable {
    func reviewActivation(requiring version: DataCompatibilityVersion) async throws
        -> DataCompatibilityActivationReview

    func updates() -> AsyncStream<Void>
}
