import Testing
@testable import ThrowCore

struct TransitPositionEstimatorTests {
    @Test func exactTripBuildsMotionTowardTheNextStop() throws {
        var estimator = TransitPositionEstimator()
        let estimates = try estimator.estimates(
            snapshots: [TransitFixture.snapshot()],
            schedule: TransitFixture.schedule(),
            at: ThrowCoreFixture.date,
        )
        let estimate = try #require(estimates.first)
        #expect(estimate.route.shortName == "A")
        #expect(estimate.nextStop.name == "Second")
        #expect(estimate.motion != nil)
        #expect(estimate.confidence == .scheduleInferred)
    }

    @Test func repeatedRunAdvancesConfidenceToFeedTracked() throws {
        var estimator = TransitPositionEstimator()
        let firstSnapshot = try TransitFixture.snapshot(nextStopRawValue: "A01N")
        _ = try estimator.estimates(
            snapshots: [firstSnapshot],
            schedule: TransitFixture.schedule(),
            at: ThrowCoreFixture.date,
        )
        let nextSnapshot = try TransitFixture.snapshot(nextStopRawValue: "A02N")
        let estimates = try estimator.estimates(
            snapshots: [nextSnapshot],
            schedule: TransitFixture.schedule(),
            at: ThrowCoreFixture.date,
        )
        #expect(estimates.first?.confidence == .feedTracked)
    }
}
