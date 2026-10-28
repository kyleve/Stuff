import Foundation
import Testing
import WhereCore

struct CalendarDayCountTests {
    private let calendar = WhereCoreTestSupport.calendar()

    @Test func commonYearHas365Days() {
        #expect(calendar.dayCount(ofYear: 2025) == 365)
        #expect(calendar.dayCount(ofYear: 2023) == 365)
    }

    @Test func leapYearHas366Days() {
        #expect(calendar.dayCount(ofYear: 2024) == 366)
        #expect(calendar.dayCount(ofYear: 2000) == 366)
    }

    /// 1900 is divisible by 100 but not 400, so the Gregorian calendar skips its
    /// leap day — the derived count must reflect that, not a naive `year % 4`.
    @Test func gregorianCentennialSkipsLeapDay() {
        #expect(calendar.dayCount(ofYear: 1900) == 365)
    }
}
