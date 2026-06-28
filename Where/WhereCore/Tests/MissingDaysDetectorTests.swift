import Foundation
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct MissingDaysDetectorTests {
    @Test func currentYearUsesBacklogCutoff() {
        let present: [DayPresence] = [
            DayPresence(date: Fixtures.day(2026, 1, 1), regions: [.california]),
        ]
        let now = Fixtures.day(2026, 1, 5)
        let issues = MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2026,
            days: present,
            now: now,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].range.start == Fixtures.day(2026, 1, 2))
        #expect(issues[0].range.end == Fixtures.day(2026, 1, 4))
        #expect(issues[0].range.dayCount == 3)
        #expect(issues[0].isDismissible == false)
    }

    @Test func futureYearReturnsEmpty() {
        // A year that hasn't started yet must not report every day as missing.
        let issues = MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2027,
            days: [],
            now: Fixtures.day(2026, 6, 15),
        ))
        #expect(issues.isEmpty)
    }

    @Test func pastYearThroughDec31() {
        let present: [DayPresence] = [
            DayPresence(date: Fixtures.day(2025, 12, 30), regions: [.california]),
        ]
        let issues = MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2025,
            days: present,
            now: Fixtures.day(2026, 6, 15),
        ))
        #expect(issues.contains { $0.range.start == Fixtures.day(2025, 12, 31) })
    }
}
