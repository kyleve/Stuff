import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct PresenceJourneyItemTests {
    @Test(arguments: [-12, 0, 14])
    func recordedFlightSortsOnItsLogicalDay(viewingOffset: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: viewingOffset * 3600))
        let flight = try RecordingFlightPreview.flight(.priorYear)
        let departure = CalendarDay(year: 2025, month: 12, day: 31)
        #expect(flight.completedDays(in: calendar) == [departure])
        let start = departure.adding(days: -3)
        let stints = PresenceTimeline.stints(from: YearReport(
            year: 2025,
            days: start.days(through: departure.adding(days: -1))
                .map { DayPresence(day: $0, regions: [.california]) }
                + [DayPresence(day: departure, regions: [.newYork])],
            totals: [.california: 3, .newYork: 1],
        ))
        let items = PresenceJourneyItem.items(
            stints: stints,
            flights: [flight],
            year: 2025,
            calendar: calendar,
        )
        #expect(items.count == 3)
        #expect(items.dropFirst().first == .flight(flight))
    }

    @Test(arguments: [-12, 0, 14])
    func dateLineFlightSplitsAtItsFirstSupportedDateInTheSelectedYear(viewingOffset: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: viewingOffset * 3600))
        let flight = try RecordingFlightPreview.flight(.dateLine)
        let start = CalendarDay(year: 2026, month: 1, day: 1)
        let stint = RegionStint(region: .newYork, start: start, end: start.adding(days: 2))
        let items = PresenceJourneyItem.items(
            stints: [stint],
            flights: [flight],
            year: 2026,
            calendar: calendar,
        )
        #expect(items == [
            .stay(RegionStint(region: .newYork, start: start, end: start)),
            .flight(flight),
            .stay(RegionStint(
                region: .newYork,
                start: start.adding(days: 1),
                end: start.adding(days: 2),
            )),
        ])
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func logicalDay(_ day: Int, month: Int = 1) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    private func date(_ day: Int, month: Int = 1, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func flight(
        day: Int,
        month: Int = 1,
        hour: Int = 12,
        pending: Bool = false,
    ) -> FlightAssessment {
        FlightAssessment(
            id: .init(recordingSource: .legacy, departureSampleID: UUID()),
            startedAt: date(day, month: month, hour: hour),
            lastObservationAt: date(
                day,
                month: month,
                hour: hour + 2,
            ),
            lastFlightAt: date(day, month: month, hour: hour + 1),
            airborneSampleIDs: [],
            groundSampleIDs: [],
            peakSpeedKMH: 900,
            progress: pending ? .awaitingArrival : .completed(arrival: .observedGround(
                firstObservedAt: date(day, month: month, hour: hour + 2),
                confirmedAt: date(day, month: month, hour: hour + 2),
            )),
            inferredEndpoints: [],
            supportedIntervals: [.init(
                start: date(day, month: month, hour: hour),
                end: date(day, month: month, hour: hour + 1),
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
            RegionStint(region: $0, start: logicalDay(1), end: logicalDay(5))
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
            #expect(segments.first?.end == logicalDay(2))
            #expect(segments.last?.start == logicalDay(3))
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
        let stints = PresenceTimeline.stints(from: report)
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
            progress: .completed(arrival: .observedGround(
                firstObservedAt: arrivedAt,
                confirmedAt: arrivedAt,
            )),
            inferredEndpoints: [],
            supportedIntervals: [.init(start: departedAt, end: arrivedAt, kind: .observedMotion)],
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
                start: start,
                end: start,
            )),
            .stay(RegionStint(
                region: .california,
                start: start,
                end: departure,
            )),
            .flight(flight),
            .stay(RegionStint(
                region: .newYork,
                start: departure,
                end: end,
            )),
        ])
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test(arguments: [false, true])
    func shorterVisitInterruptsNewYorkBeforeTheSeptember20Flight(reversed: Bool) {
        let days = (13 ... 23).map { day in
            var regions: Set<Region> = []
            if day <= 20 { regions.insert(.newYork) }
            if day == 14 { regions.insert(.other) }
            if day >= 20 { regions.insert(.california) }
            return DayPresence(day: CalendarDay(year: 2026, month: 9, day: day), regions: regions)
        }
        let report = YearReport(year: 2026, days: days, totals: [:])
        let stints = PresenceTimeline.stints(from: report)
        let flight = flight(day: 20, month: 9)
        let items = PresenceJourneyItem.items(
            stints: reversed ? stints.reversed() : stints,
            flights: [flight],
            year: 2026,
            calendar: calendar,
        )

        #expect(items == [
            .stay(RegionStint(
                region: .newYork,
                start: logicalDay(13, month: 9),
                end: logicalDay(13, month: 9),
            )),
            .stay(RegionStint(
                region: .other,
                start: logicalDay(14, month: 9),
                end: logicalDay(14, month: 9),
            )),
            .stay(RegionStint(
                region: .newYork,
                start: logicalDay(14, month: 9),
                end: logicalDay(20, month: 9),
            )),
            .flight(flight),
            .stay(RegionStint(
                region: .california,
                start: logicalDay(20, month: 9),
                end: logicalDay(23, month: 9),
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
        let stint = RegionStint(region: .california, start: logicalDay(1), end: logicalDay(3))
        #expect(PresenceJourneyItem.items(
            stints: [stint],
            flights: [crossing],
            year: 2026,
            calendar: calendar,
        ) == [.flight(crossing), .stay(stint)])
    }
}
