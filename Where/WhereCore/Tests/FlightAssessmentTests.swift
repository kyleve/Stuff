import Foundation
import Testing
import WhereCore

struct FlightAssessmentTests {
    @Test func completedDaysIncludeMidnightAndEmptyObservationDaysInTheDisplayTimezone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let departure = try #require(calendar.date(from: DateComponents(
            year: 2025,
            month: 12,
            day: 31,
            hour: 23,
        )))
        let arrival = departure.addingTimeInterval(26 * 3600)
        func flight(_ progress: FlightAssessment.Progress) -> FlightAssessment {
            FlightAssessment(
                id: .init(recordingSource: .legacy, departureSampleID: UUID()),
                startedAt: departure,
                lastObservationAt: arrival,
                lastFlightAt: departure,
                airborneSampleIDs: [],
                groundSampleIDs: [],
                peakSpeedKMH: 900,
                progress: progress,
                inferredEndpoints: [],
            )
        }
        let completed = flight(.completed(arrivedAt: arrival))
        #expect(completed.completedDays(in: calendar) == [
            CalendarDay(year: 2025, month: 12, day: 31),
            CalendarDay(year: 2026, month: 1, day: 1),
            CalendarDay(year: 2026, month: 1, day: 2),
        ])
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        #expect(completed.completedDays(in: calendar).count == 2)
        #expect(flight(.awaitingArrival).completedDays(in: calendar).isEmpty)
        #expect(flight(.flightLikely).completedDays(in: calendar).isEmpty)
    }

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
                inferredEndpoints: [],
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
