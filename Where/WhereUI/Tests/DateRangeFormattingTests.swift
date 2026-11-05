import Foundation
import Testing
import WhereCore
@testable import WhereUI

struct DateRangeFormattingTests {
    @Test func logicalDatesRemainGregorianWithoutResolvingThroughAViewingZone() {
        let skippedInApia = CalendarDay(year: 2011, month: 12, day: 30)
        #expect(DateRangeFormatting
            .abbreviated(start: skippedInApia, end: skippedInApia) == "Dec 30")
        #expect(DateRangeFormatting.abbreviated(
            start: skippedInApia,
            end: skippedInApia.adding(days: 2),
        ) == "Dec 30 – Jan 1")
    }

    @Test func historicalRangesIdentifyBothYearsAndSingleDays() {
        let day = CalendarDay(year: 2025, month: 12, day: 31)
        #expect(DateRangeFormatting.withYear(start: day, end: day) == "Dec 31, 2025")
        #expect(DateRangeFormatting.withYear(start: day, end: day.adding(days: 1))
            == "Dec 31, 2025 – Jan 1, 2026")
    }

    @Test func instantRangesHonorTheSuppliedCalendarTimeZone() throws {
        let instant = Date(timeIntervalSince1970: 1_767_225_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        #expect(DateRangeFormatting
            .abbreviated(start: instant, end: instant, calendar: calendar) == "Dec 31")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 14 * 3600))
        #expect(DateRangeFormatting
            .abbreviated(start: instant, end: instant, calendar: calendar) == "Jan 1")
    }
}
