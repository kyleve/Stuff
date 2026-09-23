import Foundation
import Testing
import WhereCore

struct FlightAssessmentTests {
    @Test func onlyFreshFlightHasATimeBasedReassessment() {
        let lastFlight = FlightTrajectoryFixtures.start
        func assessment(_ progress: FlightAssessment.Progress) -> FlightAssessment {
            FlightAssessment(
                id: .init(recordingDeviceID: nil, departureSampleID: UUID()),
                startedAt: lastFlight,
                lastObservationAt: lastFlight.addingTimeInterval(600),
                lastFlightAt: lastFlight,
                airborneSampleIDs: [],
                groundSampleIDs: [],
                peakSpeedKMH: 900,
                progress: progress,
            )
        }
        #expect(assessment(.flightLikely).nextReassessmentAt == lastFlight.addingTimeInterval(1800))
        #expect(assessment(.awaitingArrival).nextReassessmentAt == nil)
        #expect(assessment(.completed(arrivedAt: lastFlight)).nextReassessmentAt == nil)
    }
}
