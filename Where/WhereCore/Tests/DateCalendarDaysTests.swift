import Foundation
import Testing
import WhereCore

struct DateCalendarDaysTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
    }

    @Test func enumeratesEveryDayInRangeInclusive() throws {
        let days = day(2026, 2, 10).calendarDays(through: day(2026, 2, 14), in: calendar)
        #expect(days.count == 5)
        #expect(try calendar.isDate(#require(days.first), inSameDayAs: day(2026, 2, 10)))
        #expect(try calendar.isDate(#require(days.last), inSameDayAs: day(2026, 2, 14)))
    }

    @Test func normalizesEndpointsToStartOfDay() {
        let days = day(2026, 2, 10, hour: 23).calendarDays(
            through: day(2026, 2, 11, hour: 1),
            in: calendar,
        )
        #expect(days.count == 2)
        #expect(days.allSatisfy { $0 == calendar.startOfDay(for: $0) })
    }

    @Test func sameDayRangeYieldsOneDay() {
        let days = day(2026, 2, 10, hour: 6).calendarDays(
            through: day(2026, 2, 10, hour: 20),
            in: calendar,
        )
        #expect(days.count == 1)
        #expect(calendar.isDate(days[0], inSameDayAs: day(2026, 2, 10)))
    }

    @Test func endBeforeStartYieldsEmpty() {
        let days = day(2026, 2, 14).calendarDays(through: day(2026, 2, 10), in: calendar)
        #expect(days.isEmpty)
    }

    @Test func crossesMonthBoundary() {
        let days = day(2026, 1, 30).calendarDays(through: day(2026, 2, 2), in: calendar)
        #expect(days.count == 4)
        #expect(calendar.isDate(days[1], inSameDayAs: day(2026, 1, 31)))
        #expect(calendar.isDate(days[2], inSameDayAs: day(2026, 2, 1)))
    }
}
