import Foundation
import Testing
import WhereCore
import WhereUI

struct PresenceCalendarTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func report(_ days: [DayPresence], year: Int = 2026) -> YearReport {
        YearReport(year: year, days: days, totals: [:])
    }

    @Test func monthsFromReportReturnsTwelveMonthsInOrder() {
        let months = PresenceCalendar.months(from: report([]), calendar: calendar)
        #expect(months.count == 12)
        #expect(months.map(\.month) == Array(1 ... 12))
        #expect(months.allSatisfy { $0.year == 2026 })
    }

    @Test func leadingBlankCountForJanuary2026() {
        // Jan 1 2026 is a Thursday; with Sunday-first, that is 4 leading blanks.
        let months = PresenceCalendar.months(from: report([]), calendar: calendar)
        let january = months[0]
        #expect(january.month == 1)
        #expect(january.leadingBlankCount == 4)
    }

    @Test func dayRegionsAreSortedByRegionAllCasesOrder() {
        let days = [
            DayPresence(date: day(2026, 3, 15), regions: [.newYork, .california]),
        ]
        let months = PresenceCalendar.months(from: report(days), calendar: calendar)
        let marchDay = months[2].days.first { $0.dayOfMonth == 15 }
        #expect(marchDay?.regions == [.california, .newYork])
    }

    @Test func dayCountMatchesCalendarRange() {
        let months = PresenceCalendar.months(from: report([]), calendar: calendar)
        let february = months[1]
        #expect(february.days.count == 28)
    }

    @Test func dayWithNoPresenceHasEmptyRegions() {
        let months = PresenceCalendar.months(from: report([]), calendar: calendar)
        let januaryFirst = months[0].days[0]
        #expect(januaryFirst.dayOfMonth == 1)
        #expect(januaryFirst.regions.isEmpty)
    }

    @Test func dayWithPresenceIncludesMatchingRegions() {
        let days = [
            DayPresence(date: day(2026, 6, 10), regions: [.canada, .europeanUnion]),
        ]
        let months = PresenceCalendar.months(from: report(days), calendar: calendar)
        let juneDay = months[5].days.first { $0.dayOfMonth == 10 }
        #expect(juneDay?.regions == [.canada, .europeanUnion])
    }
}
