import Foundation
import Testing
@testable import WhereCore

struct CalendarDayTests {
    private let pacific = WhereCoreTestSupport.calendar(timeZone: WhereCoreTestSupport.pacific)
    private let eastern = WhereCoreTestSupport
        .calendar(timeZone: TimeZone(identifier: "America/New_York")!)

    // MARK: - Construction from a Date

    @Test func readsComponentsInTheGivenCalendarsTimeZone() {
        // 2026-04-01T04:00:00Z is midnight Eastern but 9pm the previous day Pacific.
        let instant = WhereCoreTestSupport.iso("2026-04-01T04:00:00Z")
        #expect(CalendarDay(from: instant, in: eastern) == CalendarDay(
            year: 2026,
            month: 4,
            day: 1,
        ))
        #expect(CalendarDay(from: instant, in: pacific) == CalendarDay(
            year: 2026,
            month: 3,
            day: 31,
        ))
    }

    @Test func startOfDayRoundTrips() {
        let day = CalendarDay(year: 2026, month: 7, day: 14)
        #expect(CalendarDay(from: day.startOfDay(in: pacific), in: pacific) == day)
        #expect(CalendarDay(from: day.startOfDay(in: eastern), in: eastern) == day)
    }

    // MARK: - ISO string

    @Test func descriptionIsZeroPaddedISO() {
        #expect(CalendarDay(year: 2026, month: 1, day: 5).description == "2026-01-05")
        #expect(CalendarDay(year: 2026, month: 12, day: 31).description == "2026-12-31")
    }

    @Test func isoRoundTrips() {
        let day = CalendarDay(year: 2028, month: 2, day: 29)
        #expect(CalendarDay(iso: day.description) == day)
    }

    @Test func rejectsMalformedISO() {
        #expect(CalendarDay(iso: "2026-1-5") == nil) // not zero-padded
        #expect(CalendarDay(iso: "2026-13-01") == nil) // month out of range
        #expect(CalendarDay(iso: "2026-01-00") == nil) // day out of range
        #expect(CalendarDay(iso: "not-a-date") == nil)
        #expect(CalendarDay(iso: "2026-01") == nil)
    }

    // MARK: - Ordering

    @Test func comparesByYearThenMonthThenDay() {
        #expect(CalendarDay(year: 2025, month: 12, day: 31) < CalendarDay(
            year: 2026,
            month: 1,
            day: 1,
        ))
        #expect(CalendarDay(year: 2026, month: 1, day: 31) < CalendarDay(
            year: 2026,
            month: 2,
            day: 1,
        ))
        #expect(CalendarDay(year: 2026, month: 2, day: 1) < CalendarDay(
            year: 2026,
            month: 2,
            day: 2,
        ))
    }

    // MARK: - Arithmetic

    @Test func addingDaysCrossesMonthAndYearBoundaries() {
        #expect(
            CalendarDay(year: 2026, month: 1, day: 31).adding(days: 1)
                == CalendarDay(year: 2026, month: 2, day: 1),
        )
        #expect(
            CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1)
                == CalendarDay(year: 2027, month: 1, day: 1),
        )
        #expect(
            CalendarDay(year: 2026, month: 3, day: 1).adding(days: -1)
                == CalendarDay(year: 2026, month: 2, day: 28),
        )
    }

    @Test func addingDaysHonorsLeapYears() {
        #expect(
            CalendarDay(year: 2028, month: 2, day: 28).adding(days: 1)
                == CalendarDay(year: 2028, month: 2, day: 29),
        )
        #expect(
            CalendarDay(year: 2026, month: 2, day: 28).adding(days: 1)
                == CalendarDay(year: 2026, month: 3, day: 1),
        )
    }

    @Test func arithmeticIsIndependentOfCallerTimeZone() {
        // Stepping never consults a caller calendar, so a DST transition in any
        // one zone cannot skip or duplicate a logical day.
        let start = CalendarDay(year: 2026, month: 3, day: 7) // US DST spring-forward weekend
        #expect(start.days(through: CalendarDay(year: 2026, month: 3, day: 10)).count == 4)
    }

    // MARK: - Ranges

    @Test func daysThroughIsInclusiveAndOrdered() {
        let days = CalendarDay(year: 2026, month: 1, day: 30)
            .days(through: CalendarDay(year: 2026, month: 2, day: 2))
        #expect(days == [
            CalendarDay(year: 2026, month: 1, day: 30),
            CalendarDay(year: 2026, month: 1, day: 31),
            CalendarDay(year: 2026, month: 2, day: 1),
            CalendarDay(year: 2026, month: 2, day: 2),
        ])
    }

    @Test func daysThroughIsEmptyWhenReversed() {
        #expect(
            CalendarDay(year: 2026, month: 2, day: 2)
                .days(through: CalendarDay(year: 2026, month: 1, day: 30))
                .isEmpty,
        )
    }

    // MARK: - Legacy recovery

    @Test func recoversNewYorkWrittenDayReadInPacific() {
        // A day logged at midnight Eastern, now migrated on a Pacific device: a
        // direct read lands on the previous day, the recovery init restores it.
        let nyMidnight = WhereCoreTestSupport.iso("2026-02-08T05:00:00Z")
        #expect(CalendarDay(from: nyMidnight, in: pacific) == CalendarDay(
            year: 2026,
            month: 2,
            day: 7,
        ))
        #expect(
            CalendarDay(recoveringLegacyStartOfDay: nyMidnight, in: pacific)
                == CalendarDay(year: 2026, month: 2, day: 8),
        )
    }

    @Test func recoveryLeavesSameZoneDaysUnchanged() {
        // A day logged at midnight Pacific, migrated on a Pacific device.
        let pacificMidnight = WhereCoreTestSupport.iso("2026-01-01T08:00:00Z")
        #expect(
            CalendarDay(recoveringLegacyStartOfDay: pacificMidnight, in: pacific)
                == CalendarDay(year: 2026, month: 1, day: 1),
        )
    }

    // MARK: - Codable

    @Test func codableEncodesAsISOString() throws {
        let day = CalendarDay(year: 2026, month: 7, day: 14)
        let data = try JSONEncoder().encode(day)
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-07-14\"")
        #expect(try JSONDecoder().decode(CalendarDay.self, from: data) == day)
    }
}
