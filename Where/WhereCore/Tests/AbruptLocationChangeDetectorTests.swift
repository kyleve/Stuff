import Foundation
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct AbruptLocationChangeDetectorTests {
    @Test func flagsAdjacentDisjointDays() {
        let earlier = DayPresence(date: Fixtures.day(2026, 4, 10), regions: [.california])
        let later = DayPresence(date: Fixtures.day(2026, 4, 11), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
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

    @Test func skipsOverlappingRegions() {
        let earlier = DayPresence(date: Fixtures.day(2026, 4, 10), regions: [.california, .newYork])
        let later = DayPresence(date: Fixtures.day(2026, 4, 11), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }

    @Test func skipsGapInCalendar() {
        let earlier = DayPresence(date: Fixtures.day(2026, 4, 10), regions: [.california])
        let later = DayPresence(date: Fixtures.day(2026, 4, 12), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Fixtures.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }
}
