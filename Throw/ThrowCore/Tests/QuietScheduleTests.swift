import Foundation
import Testing
@testable import ThrowCore

struct QuietScheduleTests {
    @Test func crossingMidnightIntervalContainsBothSides() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 23, minute: 0),
            end: LocalTime(hour: 6, minute: 0),
        )
        #expect(schedule.isQuiet(at: date(hour: 23, calendar: calendar), calendar: calendar))
        #expect(schedule.isQuiet(at: date(hour: 5, calendar: calendar), calendar: calendar))
        #expect(schedule
            .isQuiet(at: date(hour: 12, calendar: calendar), calendar: calendar) == false)
    }

    @Test func equalEndpointsAreInvalid() throws {
        let time = try LocalTime(hour: 8, minute: 30)
        #expect(throws: ThrowValidationError.invalidQuietInterval) {
            try QuietSchedule(start: time, end: time)
        }
    }

    @Test func scheduleUsesSuppliedAutoupdatingCalendarContext() throws {
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 22, minute: 0),
            end: LocalTime(hour: 6, minute: 0),
        )
        let instant = Date(timeIntervalSince1970: 1_767_264_400) // 2026-01-01 12:00 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = try #require(TimeZone(identifier: "Pacific/Honolulu"))
        #expect(schedule.isQuiet(at: instant, calendar: utc) == false)
        #expect(schedule.isQuiet(at: instant, calendar: honolulu))
    }

    @Test func nextBoundarySurvivesDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 22, minute: 0),
            end: LocalTime(hour: 7, minute: 0),
        )
        let beforeSpringForward = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1)),
        )
        let boundary = try #require(
            schedule.nextBoundary(after: beforeSpringForward, calendar: calendar),
        )
        #expect(calendar.component(.hour, from: boundary) == 7)
    }

    @Test func nextBoundaryUsesRemainingOccurrenceDuringRepeatedHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let schedule = try QuietSchedule(
            start: LocalTime(hour: 22, minute: 0),
            end: LocalTime(hour: 1, minute: 30),
        )
        let dayStart = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)),
        )
        let firstOneFifteen = try #require(
            calendar.nextDate(
                after: dayStart,
                matching: DateComponents(hour: 1, minute: 15),
                matchingPolicy: .strict,
                repeatedTimePolicy: .first,
                direction: .forward,
            ),
        )
        let firstOneThirty = try #require(
            calendar.nextDate(
                after: dayStart,
                matching: DateComponents(hour: 1, minute: 30),
                matchingPolicy: .strict,
                repeatedTimePolicy: .first,
                direction: .forward,
            ),
        )
        let secondOneFifteen = try #require(
            calendar.nextDate(
                after: dayStart,
                matching: DateComponents(hour: 1, minute: 15),
                matchingPolicy: .strict,
                repeatedTimePolicy: .last,
                direction: .forward,
            ),
        )
        let secondOneThirty = try #require(
            calendar.nextDate(
                after: dayStart,
                matching: DateComponents(hour: 1, minute: 30),
                matchingPolicy: .strict,
                repeatedTimePolicy: .last,
                direction: .forward,
            ),
        )

        #expect(
            schedule.nextBoundary(after: firstOneFifteen, calendar: calendar) ==
                firstOneThirty,
        )
        #expect(schedule.isQuiet(at: secondOneFifteen, calendar: calendar))
        #expect(
            schedule.nextBoundary(after: secondOneFifteen, calendar: calendar) ==
                secondOneThirty,
        )
    }

    private func date(hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    }
}
