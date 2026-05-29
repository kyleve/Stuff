import Foundation
import Testing
import WhereCore
import WhereUI

struct PresenceTimelineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func report(_ days: [DayPresence]) -> YearReport {
        YearReport(year: 2026, days: days, totals: [:])
    }

    @Test func groupsConsecutiveDaysIntoOneStint() {
        let days = (1 ... 3).map { DayPresence(date: day(2026, 1, $0), regions: [.california]) }
        let stints = PresenceTimeline.stints(from: report(days), calendar: calendar)
        #expect(stints.count == 1)
        #expect(stints[0].region == .california)
        #expect(stints[0].dayCount == 3)
        #expect(calendar.isDate(stints[0].start, inSameDayAs: day(2026, 1, 1)))
        #expect(calendar.isDate(stints[0].end, inSameDayAs: day(2026, 1, 3)))
    }

    @Test func breaksStintOnAGap() {
        let days = [
            DayPresence(date: day(2026, 1, 1), regions: [.california]),
            DayPresence(date: day(2026, 1, 2), regions: [.california]),
            DayPresence(date: day(2026, 1, 5), regions: [.california]),
        ]
        let stints = PresenceTimeline.stints(from: report(days), calendar: calendar)
        #expect(stints.count == 2)
        #expect(stints[0].dayCount == 2)
        #expect(stints[1].dayCount == 1)
        #expect(calendar.isDate(stints[1].start, inSameDayAs: day(2026, 1, 5)))
    }

    @Test func transitionDayIsSharedByBothRegions() {
        // CA Jan 1–3, with Jan 3 also New York, then NY Jan 3–5.
        let days = [
            DayPresence(date: day(2026, 1, 1), regions: [.california]),
            DayPresence(date: day(2026, 1, 2), regions: [.california]),
            DayPresence(date: day(2026, 1, 3), regions: [.california, .newYork]),
            DayPresence(date: day(2026, 1, 4), regions: [.newYork]),
            DayPresence(date: day(2026, 1, 5), regions: [.newYork]),
        ]
        let stints = PresenceTimeline.stints(from: report(days), calendar: calendar)
        #expect(stints.count == 2)
        #expect(stints[0].region == .california)
        #expect(stints[0].dayCount == 3)
        #expect(calendar.isDate(stints[0].end, inSameDayAs: day(2026, 1, 3)))
        #expect(stints[1].region == .newYork)
        #expect(stints[1].dayCount == 3)
        #expect(calendar.isDate(stints[1].start, inSameDayAs: day(2026, 1, 3)))
    }

    @Test func sortsChronologicallyAcrossRegions() {
        let days = [
            DayPresence(date: day(2026, 3, 1), regions: [.newYork]),
            DayPresence(date: day(2026, 1, 1), regions: [.california]),
            DayPresence(date: day(2026, 2, 1), regions: [.canada]),
        ]
        let stints = PresenceTimeline.stints(from: report(days), calendar: calendar)
        #expect(stints.map(\.region) == [.california, .canada, .newYork])
    }

    @Test func emptyReportProducesNoStints() {
        #expect(PresenceTimeline.stints(from: report([]), calendar: calendar).isEmpty)
    }
}
