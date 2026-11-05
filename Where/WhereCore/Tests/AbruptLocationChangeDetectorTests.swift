import Foundation
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct AbruptLocationChangeDetectorTests {
    @Test(arguments: [false, true])
    func uncertainDatesDoNotCreateTravelSuggestionsOrSuppressUnrelatedWork(unassigned: Bool) throws {
        let completeness = try Fixtures.recordingCompleteness(unassigned: unassigned)
        let days = (1 ... 4).map { day in
            DayPresence(
                day: Fixtures.calendarDay(2001, 1, day),
                regions: day.isMultiple(of: 2) ? [.newYork] : [.california],
            )
        }
        let issues = try AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(
            year: 2001,
            days: days,
            completeness: completeness,
        ))
        #expect(issues.map(\.earlierDay.day) == (unassigned ? [days[2].day] : [
            days[1].day,
            days[2].day,
        ]))
    }

    @Test func flagsAdjacentDisjointDays() throws {
        let earlier = DayPresence(
            date: Fixtures.day(2026, 4, 10),
            in: Fixtures.calendar,
            regions: [.california],
        )
        let later = DayPresence(
            date: Fixtures.day(2026, 4, 11),
            in: Fixtures.calendar,
            regions: [.newYork],
        )
        let issues = try AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.count == 1)
        #expect(issues[0].earlierDay == earlier)
        #expect(issues[0].laterDay == later)
        if case let .markTravelDay(e, l, suggested) = issues[0].resolution {
            #expect(e == earlier)
            #expect(l == later)
            #expect(suggested == [.california, .newYork])
        } else {
            Issue.record("Expected markTravelDay resolution")
        }
    }

    @Test func skipsOverlappingRegions() throws {
        let earlier = DayPresence(
            date: Fixtures.day(2026, 4, 10),
            in: Fixtures.calendar,
            regions: [.california, .newYork],
        )
        let later = DayPresence(
            date: Fixtures.day(2026, 4, 11),
            in: Fixtures.calendar,
            regions: [.newYork],
        )
        let issues = try AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }

    @Test func skipsGapInCalendar() throws {
        let earlier = DayPresence(
            date: Fixtures.day(2026, 4, 10),
            in: Fixtures.calendar,
            regions: [.california],
        )
        let later = DayPresence(
            date: Fixtures.day(2026, 4, 12),
            in: Fixtures.calendar,
            regions: [.newYork],
        )
        let issues = try AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }
}
