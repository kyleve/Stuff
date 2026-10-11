import Foundation
import Testing
@testable import WhereCore

struct AutomaticBackupIntervalTests {
    @Test func dailyWeeklyAndCalendarMonthlyDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 31,
            hour: 12,
        )))

        #expect(calendar.dateComponents(
            [.day],
            from: start,
            to: AutomaticBackupInterval.daily.nextDate(after: start, calendar: calendar),
        ).day == 1)
        #expect(calendar.dateComponents(
            [.day],
            from: start,
            to: AutomaticBackupInterval.weekly.nextDate(after: start, calendar: calendar),
        ).day == 7)
        let monthly = AutomaticBackupInterval.monthly.nextDate(after: start, calendar: calendar)
        #expect(calendar.component(.month, from: monthly) == 2)
    }
}
