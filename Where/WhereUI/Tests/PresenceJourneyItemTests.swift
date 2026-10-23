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
            progress: pending ? .awaitingArrival : .completed(arrivedAt: date(
                day,
                hour: hour + 2,
            )),
            inferredEndpoints: [],
        )
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

    @Test(arguments: ["America/Los_Angeles", "America/New_York", "UTC"])
    func departureOnLastStayDaySeparatesCaliforniaAndNewYork(timeZone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        let start = CalendarDay(year: 2026, month: 9, day: 20)
        let departure = CalendarDay(year: 2026, month: 10, day: 14)
        let end = CalendarDay(year: 2026, month: 10, day: 23)
        let days = start.days(through: end).map { day in
            var regions: Set<Region> = []
            if day <= departure { regions.insert(.california) }
            if day == start || day >= departure { regions.insert(.newYork) }
            return DayPresence(day: day, regions: regions)
        }
        let report = YearReport(year: 2026, days: days, totals: [:])
        let stints = PresenceTimeline.stints(from: report, calendar: calendar)
        let departedAt = try #require(calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: departure.startOfDay(in: calendar),
        ))
        let arrivedAt = try #require(calendar.date(byAdding: .hour, value: 6, to: departedAt))
        let flight = FlightAssessment(
            id: .init(recordingSource: .legacy, departureSampleID: UUID()),
            startedAt: departedAt,
            lastObservationAt: arrivedAt,
            lastFlightAt: departedAt,
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: .completed(arrivedAt: arrivedAt),
            inferredEndpoints: [],
        )

        let items = PresenceJourneyItem.items(
            stints: stints,
            flights: [flight],
            year: 2026,
            calendar: calendar,
        )

        #expect(items == [
            .stay(RegionStint(
                region: .newYork,
                start: start.startOfDay(in: calendar),
                end: start.startOfDay(in: calendar),
                dayCount: 1,
            )),
            .stay(RegionStint(
                region: .california,
                start: start.startOfDay(in: calendar),
                end: departure.startOfDay(in: calendar),
                dayCount: 25,
            )),
            .flight(flight),
            .stay(RegionStint(
                region: .newYork,
                start: departure.startOfDay(in: calendar),
                end: end.startOfDay(in: calendar),
                dayCount: 10,
            )),
        ])
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
