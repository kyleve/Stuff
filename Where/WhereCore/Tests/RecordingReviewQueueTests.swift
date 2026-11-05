import Foundation
import Testing
@testable import WhereCore

struct RecordingReviewQueueTests {
    @Test func splitIssuesRetainUnresolvedPartsDespiteChangedIdentifiers() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        let reference = try RecordingReviewTestSupport.reference(initial)
        let queue = try RecordingReviewQueue(references: [reference])
        let updated = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 300),
            RecordingIssueTestSupport.issue(start: 500, end: 700),
        ])
        let remaining = try queue.remaining(in: updated)
        #expect(try remaining.map(\.periods) == [
            [RecordingAssessmentTestSupport.period(100, 300)],
            [RecordingAssessmentTestSupport.period(500, 700)],
        ])
        #expect(remaining.map(\.references) == [[reference], [reference]])
        #expect(remaining.allSatisfy { $0.issue.id != reference.issueID })
        #expect(queue.originalPeriods == reference.originalPeriods)
    }

    @Test func mergedContextDoesNotAddGapsOrAdjacentWorkToTheChoice() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 300),
            RecordingIssueTestSupport.issue(start: 500, end: 700),
        ])
        let first = try RecordingReviewTestSupport.reference(initial)
        let second = try RecordingReviewTestSupport.reference(initial, issueIndex: 1)
        let queue = try RecordingReviewQueue(references: [first, second, first])
        let updated = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 0, end: 900),
        ])
        let remaining = try queue.remaining(in: updated)
        #expect(remaining.count == 1)
        let item = try #require(remaining.first)
        #expect(try item.issue.period == RecordingAssessmentTestSupport.period(0, 900))
        #expect(try item.periods == [
            RecordingAssessmentTestSupport.period(100, 300),
            RecordingAssessmentTestSupport.period(500, 700),
        ])
        #expect(item.references == [first, second])
        #expect(queue.references.count == 2)
    }

    @Test func overlappingReferencesReviewTheSameWorkOnce() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        let first = try RecordingReviewTestSupport.reference(
            initial,
            periods: [RecordingAssessmentTestSupport.period(100, 500)],
        )
        let second = try RecordingReviewTestSupport.reference(
            initial,
            periods: [RecordingAssessmentTestSupport.period(300, 700)],
        )
        let queue = try RecordingReviewQueue(references: [second, first])
        let remaining = try queue.remaining(in: initial)
        #expect(remaining.count == 1)
        #expect(try remaining.first?.periods == [RecordingAssessmentTestSupport.period(100, 700)])
        #expect(remaining.first?.references == [first, second])
        #expect(try RecordingReviewQueue(references: [first, second]) == queue)
    }

    @Test func changedLogicalYearAndNewDeviceEvidenceRemainInTheOriginalAbsoluteScope() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(
                start: 100,
                end: 900,
                days: .known([CalendarDay(year: 2000, month: 12, day: 31)]),
            ),
        ])
        let reference = try RecordingReviewTestSupport.reference(
            initial,
            historicalYear: 2000,
            query: .days(CalendarDay.yearRange(2000)),
        )
        let queue = try RecordingReviewQueue(references: [reference])
        let newDevice = RecordingDeviceID(rawValue: UUID())
        let newSample = UUID()
        let updated = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(
                start: 100,
                end: 900,
                days: .unassigned(known: [CalendarDay(year: 2001, month: 1, day: 1)]),
                problem: .competingTracks([RecordingAssessmentTestSupport.first, newDevice]),
                sampleIDs: [newSample],
            ),
            RecordingIssueTestSupport.issue(start: 1000, end: 1200),
        ])
        let remaining = try queue.remaining(in: updated)
        #expect(remaining.count == 1)
        #expect(remaining.first?.issue.days == .unassigned(known: [
            CalendarDay(year: 2001, month: 1, day: 1),
        ]))
        #expect(remaining.first?.issue.sampleIDs == [newSample])
        #expect(remaining.first?.references == [reference])
        #expect(reference.context.historicalYear == 2000)
    }

    @Test func compatiblePolicyChangeUsesTheCurrentFullAssessment() throws {
        let raw = try RecordingIssueTestSupport.issue(start: 100, end: 900)
        let original = DataSemanticsVersion(major: 1, minor: 0, patch: 0)
        let current = DataSemanticsVersion(major: 1, minor: 2, patch: 3)
        let before = try RecordingReviewTestSupport.snapshot([raw], version: original)
        let reference = try RecordingReviewTestSupport.reference(before)
        let queue = try RecordingReviewQueue(references: [reference])
        let after = try RecordingReviewTestSupport.snapshot([raw], version: current)
        let remaining = try queue.remaining(in: after)
        #expect(remaining.first?.issue.policyVersion == current)
        #expect(remaining.first?.references.first?.policyVersion == original)
    }

    @Test func missingAssessmentCannotClaimResolutionAndDoesNotLoseRetryScope() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 900),
        ])
        let reference = try RecordingReviewTestSupport.reference(initial)
        let queue = try RecordingReviewQueue(references: [reference])
        let partial = try RecordingReviewTestSupport.snapshot([], periods: [
            RecordingAssessmentTestSupport.period(100, 400),
            RecordingAssessmentTestSupport.period(500, 900),
        ])
        #expect(throws: RecordingReviewQueue.ValidationError.incompleteAssessment) {
            try queue.remaining(in: partial)
        }
        #expect(queue.references == [reference])
        #expect(try queue.remaining(in: initial).count == 1)
        let complete = try RecordingReviewTestSupport.snapshot([])
        #expect(try queue.remaining(in: complete).isEmpty)
    }

    @Test func anotherGenerationOrServiceCannotResolveOriginalWork() throws {
        let raw = try RecordingIssueTestSupport.issue(start: 100, end: 900)
        let initial = try RecordingReviewTestSupport.snapshot([raw])
        let reference = try RecordingReviewTestSupport.reference(initial)
        let queue = try RecordingReviewQueue(references: [reference])
        let reset = try RecordingReviewTestSupport.snapshot(
            [raw],
            generationID: .init(rawValue: UUID()),
        )
        #expect(throws: RecordingReviewQueue.ValidationError.dataGenerationChanged) {
            try queue.remaining(in: reset)
        }
        #expect(throws: RecordingReviewQueue.ValidationError.dataGenerationChanged) {
            try RecordingReviewQueue(references: [
                reference,
                RecordingReviewTestSupport.reference(reset),
            ])
        }
        let replacement = try RecordingReviewTestSupport.snapshot(
            [raw],
            scopeID: .init(rawValue: UUID()),
        )
        #expect(throws: RecordingReviewQueue.ValidationError.differentServiceScope) {
            try queue.remaining(in: replacement)
        }
        #expect(throws: RecordingReviewQueue.ValidationError.differentServiceScope) {
            try RecordingReviewQueue(references: [
                reference,
                RecordingReviewTestSupport.reference(replacement),
            ])
        }
    }

    @Test func incompatibleMajorCannotResolveOrJoinTheQueue() throws {
        let raw = try RecordingIssueTestSupport.issue(start: 100, end: 900)
        let initial = try RecordingReviewTestSupport.snapshot([raw])
        let reference = try RecordingReviewTestSupport.reference(initial)
        let queue = try RecordingReviewQueue(references: [reference])
        let future = try RecordingReviewTestSupport.snapshot(
            [raw],
            version: .init(major: 2, minor: 0, patch: 0),
        )
        #expect(throws: RecordingReviewQueue.ValidationError.incompatiblePolicy) {
            try queue.remaining(in: future)
        }
        #expect(throws: RecordingReviewQueue.ValidationError.incompatiblePolicy) {
            try RecordingReviewQueue(references: [
                reference,
                RecordingReviewTestSupport.reference(future),
            ])
        }
    }

    @Test func creatingAnEmptyQueueIsNotSuccessfulReassessment() {
        #expect(throws: RecordingReviewQueue.ValidationError.emptyQueue) {
            try RecordingReviewQueue(references: [])
        }
    }
}
