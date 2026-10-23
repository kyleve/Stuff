import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct PresenceJourneyItemTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func flight(day: Int, hour: Int = 12, pending: Bool = false) -> FlightAssessment {
        FlightAssessment(
            id: .init(recordingSource: .legacy, departureSampleID: UUID()),
            startedAt: date(day, hour: hour),
            lastObservationAt: date(
                day,
                hour: hour + 2,
            ),
            lastFlightAt: date(day, hour: hour + 1),
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: pending ? .awaitingArrival : .completed(arrival: .observedGround(
                firstObservedAt: date(
                    day,
                    hour: hour + 2,
                ),
                confirmedAt: date(
                    day,
                    hour: hour + 2,
                ),
            )),
            inferredEndpoints: [],
            supportedIntervals: [.init(
                start: date(day, hour: hour),
                end: date(day, hour: hour + 1),
                kind: .observedMotion,
            )],
        )
    }

    @Test func uncertainArrivalKeepsTheFlightWithoutSplittingUnobservedDays() {
        let original = flight(day: 3)
        let uncertain = FlightAssessment(
            id: original.id,
            startedAt: original.startedAt,
            lastObservationAt: date(7),
            lastFlightAt: original.lastFlightAt,
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: .completed(arrival: .uncertainTiming(
                lastSupportedTravelAt: original.lastFlightAt,
                firstObservedAt: date(7),
                confirmedAt: date(7, hour: 1),
            )),
            inferredEndpoints: [],
            supportedIntervals: original.supportedIntervals,
        )
        #expect(uncertain.completedDays(in: calendar) == [CalendarDay(
            year: 2026,
            month: 1,
            day: 3,
        )])
        #expect(PresenceJourneyItem.items(
            stints: [],
            flights: [uncertain],
            year: 2026,
            calendar: calendar,
        ) == [.flight(uncertain)])
    }

    @Test func splitsOverlappingStaysWithoutChangingAnyRegionDay() {
        let stints = [Region.california, .newYork].map {
            RegionStint(region: $0, start: date(1), end: date(5), dayCount: 5)
        }
        let flight = flight(day: 3)
        let items = PresenceJourneyItem.items(
            stints: stints,
            flights: [flight, flight],
            year: 2026,
            calendar: calendar,
        )
        #expect(items.count == 5)
        #expect(items[2] == .flight(flight))
        for region in [Region.california, .newYork] {
            let segments = items.compactMap { item -> RegionStint? in
                if case let .stay(stint) = item, stint.region == region { return stint }
                return nil
            }
            #expect(segments.map(\.dayCount) == [2, 3])
            #expect(segments.first?.end == date(2))
            #expect(segments.last?.start == date(3))
        }
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func flightOnlyHistoryIsChronologicalAndExcludesPendingAndOtherYears() {
        let morning = flight(day: 3, hour: 8)
        let evening = flight(day: 3, hour: 18)
        let items = PresenceJourneyItem.items(
            stints: [],
            flights: [evening, flight(day: 4, pending: true), morning],
            year: 2026,
            calendar: calendar,
        )
        #expect(items == [.flight(morning), .flight(evening)])
        #expect(PresenceJourneyItem.items(
            stints: [],
            flights: [morning],
            year: 2027,
            calendar: calendar,
        ).isEmpty)
    }

    @Test func equalDepartureTimesKeepDeviceIdentitiesAndStableOrdering() {
        let first = flight(day: 3)
        let second = FlightAssessment(
            id: .init(
                recordingSource: .device(RecordingDeviceID(rawValue: UUID())),
                departureSampleID: first.id.departureSampleID,
            ),
            startedAt: first.startedAt,
            lastObservationAt: first.lastObservationAt,
            lastFlightAt: first.lastFlightAt,
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: first.peakSpeedKMH,
            progress: first.progress,
            inferredEndpoints: [],
            supportedIntervals: [.init(
                start: first.startedAt,
                end: first.lastFlightAt,
                kind: .observedMotion,
            )],
        )
        let forward = PresenceJourneyItem.items(
            stints: [],
            flights: [first, second],
            year: 2026,
            calendar: calendar,
        )
        let reverse = PresenceJourneyItem.items(
            stints: [],
            flights: [second, first],
            year: 2026,
            calendar: calendar,
        )
        #expect(forward.count == 2)
        #expect(forward == reverse)
    }

    @Test func flightCrossingNewYearPrecedesFirstStay() {
        let crossing = flight(day: 0, hour: 23)
        let stint = RegionStint(region: .california, start: date(1), end: date(3), dayCount: 3)
        #expect(PresenceJourneyItem.items(
            stints: [stint],
            flights: [crossing],
            year: 2026,
            calendar: calendar,
        ) == [.flight(crossing), .stay(stint)])
    }
}
