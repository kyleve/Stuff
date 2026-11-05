import Foundation
import Testing
@testable import WhereCore

struct RecordingReviewSnapshotTests {
    @Test func assessmentCoveragePreservesGapsAndNormalizesOverlap() throws {
        let first = try RecordingAssessmentTestSupport.period(0, 100)
        let second = try RecordingAssessmentTestSupport.period(200, 300)
        let overlap = try RecordingAssessmentTestSupport.period(250, 400)
        let snapshot = try RecordingReviewTestSupport.snapshot(
            [],
            periods: [overlap, first, second],
        )
        #expect(try snapshot.assessedPeriods == [
            first,
            RecordingAssessmentTestSupport.period(200, 400),
        ])
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.covers([first, second]))
        #expect(try snapshot.covers([RecordingAssessmentTestSupport.period(0, 400)]) == false)
    }

    @Test func issueOutsideTheAssessedPeriodsFailsRatherThanInventingCoverage() throws {
        let issue = try RecordingIssueTestSupport.issue(start: 90, end: 110)
        #expect(throws: RecordingReviewSnapshot.ValidationError.issueOutsideAssessment) {
            try RecordingReviewTestSupport.snapshot(
                [issue],
                periods: [RecordingAssessmentTestSupport.period(0, 100)],
            )
        }
    }

    @Test func invalidDecodedPeriodFailsEvenWhenNoIssuesRemain() throws {
        let invalid = try JSONDecoder().decode(
            RecordingPeriod.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingReviewTestSupport.snapshot([], periods: [invalid])
        }
    }

    @Test func anEmptyAssessmentCannotClaimResolution() {
        #expect(throws: RecordingReviewSnapshot.ValidationError.emptyAssessment) {
            try RecordingReviewTestSupport.snapshot([], periods: [])
        }
    }
}
