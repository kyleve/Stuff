import Testing
@testable import WhereCore

struct RecordingReviewReferenceTests {
    @Test func originalPeriodsRemainIndependentOfTheDerivedIssueAndQuery() throws {
        let snapshot = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        let first = try RecordingAssessmentTestSupport.period(200, 300)
        let second = try RecordingAssessmentTestSupport.period(700, 800)
        let query = LocationHistoryQuery.days(CalendarDay.yearRange(2001))
        let reference = try RecordingReviewTestSupport.reference(
            snapshot,
            periods: [second, first, first],
            query: query,
        )
        #expect(reference.originalPeriods == [first, second])
        #expect(reference.issueID == snapshot.issues.first?.id)
        #expect(reference.context.query == query)
        #expect(reference.context.historicalYear == 2001)
        #expect(reference.generationID == snapshot.generationID)
        #expect(reference.scopeID == snapshot.scopeID)
        #expect(reference.policyVersion == snapshot.policyVersion)
    }

    @Test func referenceCannotClaimAnIssueFromAnotherAssessment() throws {
        let before = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        let after = try RecordingReviewTestSupport.snapshot([])
        let issue = try #require(before.issues.first)
        #expect(throws: RecordingReviewReference.ValidationError.unknownIssue) {
            try RecordingReviewReference(
                issue: issue,
                originalPeriods: [issue.period],
                context: .init(historicalYear: 2001, query: .instants(issue.period)),
                snapshot: after,
            )
        }
    }

    @Test func originalScopeCannotExpandPastTheIssueOrTheQuery() throws {
        let snapshot = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        #expect(throws: RecordingReviewReference.ValidationError.scopeOutsideIssue) {
            try RecordingReviewTestSupport.reference(
                snapshot,
                periods: [RecordingAssessmentTestSupport.period(0, 900)],
            )
        }
        #expect(throws: RecordingReviewReference.ValidationError.scopeOutsideQuery) {
            try RecordingReviewTestSupport.reference(
                snapshot,
                query: .instants(RecordingAssessmentTestSupport.period(200, 900)),
            )
        }
        #expect(throws: RecordingReviewReference.ValidationError.emptyScope) {
            try RecordingReviewTestSupport.reference(snapshot, periods: [])
        }
    }
}
