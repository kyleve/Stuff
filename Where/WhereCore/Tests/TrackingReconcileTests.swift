import Testing
import WhereCore

/// Mirrors [`TrackingReconciliation`](../../Specifications/TrackingReconciliation/README.md)
/// properties on the pure decision layer — no `Task`, ingestor, or session wiring.
struct TrackingReconcileTests {
    @Test func effectiveTrackingRequiresAlwaysAuthorization() {
        #expect(TrackingReconcile.effectiveTracking(
            desired: true,
            authorizationAllowsBackground: true,
        ))
        #expect(!TrackingReconcile.effectiveTracking(
            desired: true,
            authorizationAllowsBackground: false,
        ))
        #expect(!TrackingReconcile.effectiveTracking(
            desired: false,
            authorizationAllowsBackground: true,
        ))
    }

    @Test func preemptInFlightStopWhenTargetIsOff() {
        #expect(TrackingReconcile.shouldPreemptInFlightStop(targetEffective: false))
        #expect(!TrackingReconcile.shouldPreemptInFlightStop(targetEffective: true))
    }

    @Test func publishOnlyWhenTargetMatchesAndNothingPending() {
        #expect(TrackingReconcile.shouldPublish(
            target: false,
            currentEffective: false,
            reconcilePending: false,
        ))
        #expect(!TrackingReconcile.shouldPublish(
            target: false,
            currentEffective: true,
            reconcilePending: false,
        ))
        #expect(!TrackingReconcile.shouldPublish(
            target: false,
            currentEffective: false,
            reconcilePending: true,
        ))
    }

    @Test func coalescedDisableDuringInFlightStartDoesNotPublishStaleTrue() {
        // Modeled sequence: enable, disable while start awaits — target is false,
        // current effective false, but an older iteration captured target true.
        let targetCapturedForIteration = true
        let currentEffective = TrackingReconcile.effectiveTracking(
            desired: false,
            authorizationAllowsBackground: true,
        )
        #expect(!TrackingReconcile.shouldPublish(
            target: targetCapturedForIteration,
            currentEffective: currentEffective,
            reconcilePending: false,
        ))
        #expect(TrackingReconcile.publishedAtQuiescence(
            desired: false,
            authorizationAllowsBackground: true,
        ) == false)
    }

    @Test func quiescenceAfterMatchingEnablePublishesTrue() {
        #expect(TrackingReconcile.shouldPublish(
            target: true,
            currentEffective: true,
            reconcilePending: false,
        ))
        #expect(TrackingReconcile.publishedAtQuiescence(
            desired: true,
            authorizationAllowsBackground: true,
        ))
    }
}
