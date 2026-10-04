import Foundation
import Testing
import WhereCore

struct FlightAssessmentTests {
    @Test func onlyFreshFlightHasATimeBasedReassessment() {
        let lastFlight = FlightTrajectoryFixtures.start
        func assessment(_ progress: FlightAssessment.Progress) -> FlightAssessment {
            FlightAssessment(
                id: .init(recordingSource: .legacy, departureSampleID: UUID()),
                startedAt: lastFlight,
                lastObservationAt: lastFlight.addingTimeInterval(600),
                lastFlightAt: lastFlight,
                airborneSampleIDs: [],
                groundSampleIDs: [],
                peakSpeedKMH: 900,
                progress: progress,
            )
        }
        #expect(assessment(.flightLikely).reassessment == .at(lastFlight.addingTimeInterval(1800)))
        #expect(assessment(.awaitingArrival).reassessment == .whenEvidenceChanges)
        #expect(assessment(.completed(arrivedAt: lastFlight)).reassessment == .whenEvidenceChanges)
        #expect(assessment(.flightLikely).isPending)
        #expect(assessment(.awaitingArrival).isPending)
        #expect(assessment(.completed(arrivedAt: lastFlight)).isPending == false)
    }
}
