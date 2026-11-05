import Foundation
import Testing
import WhereCore
import WhereUI

struct PresenceTimelineTests {
    @Test func logicalStaysKeepDatesSkippedBySomeTimeZones() {
        let days = (29 ... 31).map { DayPresence(
            day: CalendarDay(year: 2011, month: 12, day: $0),
            regions: [.california],
        ) }
        let report = YearReport(year: 2011, days: days, totals: [.california: 3])
        let stints = PresenceTimeline.stints(from: report)
        #expect(stints.count == 1)
        #expect(stints.first?.dayCount == 3)
    }

    @Test func logicalStayIdentityUsesItsRegionAndCalendarDay() throws {
        let day = CalendarDay(year: 2025, month: 12, day: 31)
        let report = YearReport(
            year: 2025,
            days: [DayPresence(day: day, regions: [.california])],
            totals: [.california: 1],
        )
        let stint = try #require(PresenceTimeline.stints(from: report).first)
        #expect(stint.id.region == .california)
        #expect(stint.id.start == day)
    }

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
        let days = (1 ... 3).map { DayPresence(
            date: day(2026, 1, $0),
            in: calendar,
            regions: [.california],
        ) }
        let stints = PresenceTimeline.stints(from: report(days))
        #expect(stints.count == 1)
        #expect(stints[0].region == .california)
        #expect(stints[0].dayCount == 3)
        #expect(stints[0].start == CalendarDay(year: 2026, month: 1, day: 1))
        #expect(stints[0].end == CalendarDay(year: 2026, month: 1, day: 3))
    }

    @Test func breaksStintOnAGap() {
        let days = [
            DayPresence(date: day(2026, 1, 1), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 1, 2), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 1, 5), in: calendar, regions: [.california]),
        ]
        let stints = PresenceTimeline.stints(from: report(days))
        #expect(stints.count == 2)
        #expect(stints[0].dayCount == 2)
        #expect(stints[1].dayCount == 1)
        #expect(stints[1].start == CalendarDay(year: 2026, month: 1, day: 5))
    }

    @Test func transitionDayIsSharedByBothRegions() {
        // CA Jan 1–3, with Jan 3 also New York, then NY Jan 3–5.
        let days = [
            DayPresence(date: day(2026, 1, 1), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 1, 2), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 1, 3), in: calendar, regions: [.california, .newYork]),
            DayPresence(date: day(2026, 1, 4), in: calendar, regions: [.newYork]),
            DayPresence(date: day(2026, 1, 5), in: calendar, regions: [.newYork]),
        ]
        let stints = PresenceTimeline.stints(from: report(days))
        #expect(stints.count == 2)
        #expect(stints[0].region == .california)
        #expect(stints[0].dayCount == 3)
        #expect(stints[0].end == CalendarDay(year: 2026, month: 1, day: 3))
        #expect(stints[1].region == .newYork)
        #expect(stints[1].dayCount == 3)
        #expect(stints[1].start == CalendarDay(year: 2026, month: 1, day: 3))
    }

    @Test func sortsChronologicallyAcrossRegions() {
        let days = [
            DayPresence(date: day(2026, 3, 1), in: calendar, regions: [.newYork]),
            DayPresence(date: day(2026, 1, 1), in: calendar, regions: [.california]),
            DayPresence(date: day(2026, 2, 1), in: calendar, regions: [.canada]),
        ]
        let stints = PresenceTimeline.stints(from: report(days))
        #expect(stints.map(\.region) == [.california, .canada, .newYork])
    }

    @Test func emptyReportProducesNoStints() {
        #expect(PresenceTimeline.stints(from: report([])).isEmpty)
    }
}
