import Foundation
import Testing
@testable import WhereCore

struct HistoryCompletenessTests {
    @Test(arguments: [false, true])
    func inferenceDatesAgreeWithScopedEligibilityWithoutInventingAssignments(
        unassigned: Bool,
    ) throws {
        let completeness = try DataIssueDetectorFixtures
            .recordingCompleteness(unassigned: unassigned)
        let days = try completeness.daysRequiringReview
        let january1 = CalendarDay(year: 2001, month: 1, day: 1)
        #expect(days == (unassigned ? [january1, january1.adding(days: 1)] : [january1]))
        #expect(completeness.affectedDays == (unassigned ? [] : [january1]))
        for day in january1.days(through: january1.adding(days: 4)) {
            #expect(try completeness.restricted(to: day ... day).isComplete == !days.contains(day))
        }
    }

    @Test func unassignedInferenceDatesRespectHalfOpenOffsetBoundaries() throws {
        let completeness = try HistoryCompleteness.recording(
            version: RecordingEvidencePolicy.version,
            days: CalendarDay.yearRange(2001),
            issues: [.init(
                period: RecordingAssessmentTestSupport.period(42 * 3600, 42 * 3600 + 1),
                problem: .recordingDay([RecordingAssessmentTestSupport.first]),
                days: .unassigned(known: []),
                sampleIDs: [],
            )],
        )
        #expect(try completeness.daysRequiringReview == [
            CalendarDay(year: 2001, month: 1, day: 2),
            CalendarDay(year: 2001, month: 1, day: 3),
        ])
        #expect(completeness.affectedDays.isEmpty)
    }

    @Test func countsDistinctCandidateDatesAndRetainsTheFullPolicy() throws {
        let observations = try RecordingHistorySelectionTestSupport.midnightObservations()
        let selection = try RecordingHistorySelectionTestSupport.years(
            observations,
            from: 1999,
            through: 2002,
        )
        let prior = try HistoryCompleteness(selection: selection, days: CalendarDay.yearRange(2000))
        let next = try HistoryCompleteness(selection: selection, days: CalendarDay.yearRange(2001))
        #expect(prior.affectedDays == [.init(year: 2000, month: 12, day: 31)])
        #expect(next.affectedDays == [.init(year: 2001, month: 1, day: 1)])
        #expect(!prior.isComplete && !next.isComplete)
        #expect(!prior.hasUnassignedDays)
        guard case let .recording(version, _, _) = prior else {
            Issue.record("Expected recording completeness")
            return
        }
        #expect(version == RecordingEvidencePolicy.version)
        #expect(throws: UnresolvedHistoryError.self) { try prior.requireComplete() }
    }

    @Test func unknownAssignmentsRemainSeparateAndCannotBlockUnrelatedYears() throws {
        let observation = try RecordingAssessmentTestSupport.observation(
            seconds: 100,
            assignment: .unresolved,
        )
        let selection = try RecordingHistorySelectionTestSupport.years(
            [observation],
            from: 1999,
            through: 2002,
        )
        let current = try HistoryCompleteness(
            selection: selection,
            days: CalendarDay.yearRange(2001),
        )
        #expect(current.affectedDays.isEmpty)
        #expect(current.hasUnassignedDays)
        #expect(!current.isComplete)
        let old = try HistoryCompleteness(selection: selection, days: CalendarDay.yearRange(1999))
        #expect(old.isComplete)
        try old.requireComplete()
    }

    @Test func narrowingScopeRetainsTheOriginalIssueAndRejectsUnassessedExpansion() throws {
        let observation = try RecordingAssessmentTestSupport.observation(
            seconds: 100,
            assignment: .unresolved,
        )
        let selection = try RecordingHistorySelectionTestSupport.years(
            [observation],
            from: 1999,
            through: 2002,
        )
        let year = try HistoryCompleteness(selection: selection, days: CalendarDay.yearRange(2001))
        let january1 = CalendarDay(year: 2001, month: 1, day: 1)
        let january3 = CalendarDay(year: 2001, month: 1, day: 3)
        #expect(try year.restricted(to: january1 ... january1).issues == year.issues)
        #expect(try year.restricted(to: january3 ... january3).isComplete)
        #expect(throws: HistoryCompleteness.ValidationError.self) {
            try year.restricted(to: CalendarDay.yearRange(2002))
        }
    }

    @Test func multipleConflictsOnOneDateCountOnce() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: true,
            region: .newYork,
        )
        let selection = try RecordingHistorySelectionTestSupport.years(
            first + second,
            from: 2001,
            through: 2001,
        )
        #expect(selection.issues.count > 1)
        let completeness = try HistoryCompleteness(
            selection: selection,
            days: CalendarDay.yearRange(2001),
        )
        #expect(completeness.affectedDays == [.init(year: 2001, month: 1, day: 1)])
        #expect(!completeness.hasUnassignedDays)
    }

    @Test func aNarrowProjectionCannotAuthorizeAnUnassessedYear() throws {
        let selection = try RecordingHistorySelectionTestSupport.resolve([])
        let projection = LocationHistoryProjection(
            samples: [],
            revisions: [],
            contract: .recording(selection),
        )
        #expect(throws: HistoryCompleteness.ValidationError.self) {
            try projection.completeness(in: CalendarDay.yearRange(2001))
        }
    }
}
