import Foundation

/// Pure decision logic for the tracking-toggle protocol in
/// [`TrackingReconciliation`](../../Specifications/TrackingReconciliation/README.md).
///
/// Maps to the TLA+ variables `desired`, `ingestorActive`, `published`, `worker`,
/// and `target`. Async orchestration stays in ``WhereSession``; this type is the
/// declarative digest the spec and production code share.
///
/// - Property ``shouldPublish(target:currentEffective:reconcilePending:)`` ↔
///   `CorrectAtQuiescence` (publish only when intent settled).
/// - Property ``shouldPreemptInFlightStop(targetEffective:)`` ↔ coalesced stop
///   while a start is parked on an await.
public enum TrackingReconcile: Sendable {
    /// Worker lane phase in the coalesced design (`Coalesced.cfg`).
    public enum WorkerPhase: String, Sendable, Hashable, CaseIterable {
        case idle
        case ready
        case starting
        case stopping
    }

    /// Whether background tracking should be active given intent and authorization.
    public static func effectiveTracking(
        desired: Bool,
        authorizationAllowsBackground: Bool,
    ) -> Bool {
        desired && authorizationAllowsBackground
    }

    /// When a reconcile is already in flight and the latest intent is *off*,
    /// stop the ingestor immediately instead of awaiting the parked start.
    public static func shouldPreemptInFlightStop(targetEffective: Bool) -> Bool {
        !targetEffective
    }

    /// After a side effect completes, whether ``WhereSession/isTracking`` may update.
    public static func shouldPublish(
        target: Bool,
        currentEffective: Bool,
        reconcilePending: Bool,
    ) -> Bool {
        currentEffective == target && !reconcilePending
    }

    /// UI published state once every command has settled (`CorrectAtQuiescence`).
    public static func publishedAtQuiescence(
        desired: Bool,
        authorizationAllowsBackground: Bool,
    ) -> Bool {
        effectiveTracking(
            desired: desired,
            authorizationAllowsBackground: authorizationAllowsBackground,
        )
    }
}
