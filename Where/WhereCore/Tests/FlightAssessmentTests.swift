import Foundation
import Testing
import WhereCore

struct FlightAssessmentTests {
    @Test func completedDaysAndDisplayPeriodsDoNotBridgeUnsupportedIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = FlightTrajectoryFixtures.start
        let later = start.addingTimeInterval(3 * 86400)
        let flight = FlightAssessment(
            id: .init(
                recordingSource: .legacy,
                departureSampleID: FlightTrajectoryFixtures.sampleID(1),
            ),
            startedAt: start,
            lastObservationAt: later.addingTimeInterval(1200),
            lastFlightAt: later,
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: .completed(arrival: .observedGround(
                firstObservedAt: later,
                confirmedAt: later.addingTimeInterval(1200),
            )),
            inferredEndpoints: [],
            supportedIntervals: [
                .init(start: start, end: start.addingTimeInterval(300), kind: .observedMotion),
                .init(
                    start: start.addingTimeInterval(300),
                    end: start.addingTimeInterval(600),
                    kind: .observedMotion,
                ),
                .init(start: later, end: later.addingTimeInterval(60), kind: .displacement),
            ],
        )
        #expect(flight.completedDays(in: calendar) == [
            CalendarDay(from: start, in: calendar),
            CalendarDay(from: later, in: calendar),
        ])
        #expect(flight.supportedPeriods == [
            DateInterval(start: start, duration: 600),
            DateInterval(start: later, duration: 60),
        ])
    }

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
                supportedIntervals: [.init(start: departure, end: arrival, kind: .observedMotion)],
            )
        }
        let completed = flight(.completed(arrival: .observedGround(
            firstObservedAt: arrival,
            confirmedAt: arrival,
        )))
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
                supportedIntervals: [.init(
                    start: lastFlight,
                    end: lastFlight,
                    kind: .observedMotion,
                )],
            )
        }
        #expect(assessment(.flightLikely).reassessment == .at(lastFlight.addingTimeInterval(1800)))
        #expect(assessment(.awaitingArrival).reassessment == .whenEvidenceChanges)
        #expect(assessment(.completed(arrival: .observedGround(
            firstObservedAt: lastFlight,
            confirmedAt: lastFlight,
        ))).reassessment == .whenEvidenceChanges)
        #expect(assessment(.flightLikely).isPending)
        #expect(assessment(.awaitingArrival).isPending)
        #expect(assessment(.completed(arrival: .observedGround(
            firstObservedAt: lastFlight,
            confirmedAt: lastFlight,
        ))).isPending == false)
    }
}
