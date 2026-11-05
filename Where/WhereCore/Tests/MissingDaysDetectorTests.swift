import Foundation
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct MissingDaysDetectorTests {
    @Test(arguments: [false, true])
    func disputedHistoryNeedsRecordingReviewInsteadOfBackfill(unassigned: Bool) throws {
        let completeness = try Fixtures.recordingCompleteness(unassigned: unassigned)
        let issues = try MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2001,
            now: Fixtures.day(2001, 1, 5),
            completeness: completeness,
        ))
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.range.start == Fixtures.calendarDay(2001, 1, unassigned ? 3 : 2))
        #expect(issue.range.end == Fixtures.calendarDay(2001, 1, 4))
    }

    @Test func currentYearUsesBacklogCutoff() throws {
        let present: [DayPresence] = [
            DayPresence(
                date: Fixtures.day(2026, 1, 1),
                in: Fixtures.calendar,
                regions: [.california],
            ),
        ]
        let now = Fixtures.day(2026, 1, 5)
        let issues = try MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2026,
            days: present,
            now: now,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].range.start == Fixtures.calendarDay(2026, 1, 2))
        #expect(issues[0].range.end == Fixtures.calendarDay(2026, 1, 4))
        #expect(issues[0].range.dayCount == 3)
        #expect(issues[0].isDismissible == false)
    }

    @Test func futureYearReturnsEmpty() throws {
        // A year that hasn't started yet must not report every day as missing.
        let issues = try MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2027,
            days: [],
            now: Fixtures.day(2026, 6, 15),
        ))
        #expect(issues.isEmpty)
    }

    @Test func pastYearThroughDec31() throws {
        let present: [DayPresence] = [
            DayPresence(
                date: Fixtures.day(2025, 12, 30),
                in: Fixtures.calendar,
                regions: [.california],
            ),
        ]
        let issues = try MissingDaysDetector().detectIssues(in: Fixtures.input(
            year: 2025,
            days: present,
            now: Fixtures.day(2026, 6, 15),
        ))
        #expect(issues.contains { $0.range.start == Fixtures.calendarDay(2025, 12, 31) })
    }
}
