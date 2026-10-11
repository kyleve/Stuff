import Testing
@testable import WhereCore

struct GPSCorrectionReviewTests {
    @Test(arguments: [false, true])
    func dismissingAMixedReviewRetainsPendingEvidence(pendingFirst: Bool) throws {
        let trace = FlightTrajectoryFixtures.mixedFlights(
            pendingFirst: pendingFirst,
            separateDevices: false,
        )
        let review = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples,
            attributor: SampleCorrectionTestSupport.attribution,
            now: trace.readyAt,
        ).first)
        try #require(review.proposal != nil)

        let dismissed = try #require(review.dismissingProposal())

        #expect(dismissed.id == review.id)
        #expect(dismissed.day == review.day)
        #expect(dismissed.points == review.points)
        #expect(dismissed.flights == review.flights)
        #expect(dismissed.isPending)
        #expect(dismissed.flight?.isPending == true)
        #expect(dismissed.proposal == nil)
        #expect(dismissed.dismissingProposal() == dismissed)
    }
}
