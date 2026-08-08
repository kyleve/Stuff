import Foundation
import Testing
@testable import WhereUI

struct YearExportDefaultsTests {
    @Test func currentYearDefaultsToPreviousFromJanuaryThroughMarch() throws {
        let calendar = YearPDFTestSupport.calendar
        for month in 1 ... 3 {
            let now = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: month,
                day: 15,
            )))
            #expect(YearExportDefaults.selectedYear(
                displayedYear: 2026,
                now: now,
                calendar: calendar,
            ) == 2025)
        }
    }

    @Test func currentYearRollsToCurrentInApril() throws {
        let calendar = YearPDFTestSupport.calendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        #expect(YearExportDefaults.selectedYear(
            displayedYear: 2026,
            now: now,
            calendar: calendar,
        ) == 2026)
    }

    @Test func nonCurrentDisplayedYearHasPriorityAndRemainsAvailableOutsideRange() throws {
        let calendar = YearPDFTestSupport.calendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        #expect(YearExportDefaults.selectedYear(
            displayedYear: 2018,
            now: now,
            calendar: calendar,
        ) == 2018)
        #expect(YearExportDefaults.availableYears(
            displayedYear: 2018,
            now: now,
            calendar: calendar,
        ) == [2026, 2025, 2024, 2023, 2022, 2021, 2018])
    }
}
