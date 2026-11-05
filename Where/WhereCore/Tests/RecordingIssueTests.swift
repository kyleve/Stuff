import Foundation
import Testing
@testable import WhereCore

struct RecordingIssueTests {
    @Test func contiguousJourneyRetainsChangingProblemsAndAllCandidateDays() throws {
        let sampleID = UUID()
        let first = try RecordingIssueTestSupport.issue(start: 0, end: 600, sampleIDs: [sampleID])
        let second = try RecordingIssueTestSupport.issue(
            start: 600,
            end: 1200,
            days: .known([RecordingIssueTestSupport.secondDay]),
            problem: .recordingDay([RecordingAssessmentTestSupport.first]),
        )
        let grouped = try RecordingIssue.grouped(
            [first, second],
            version: RecordingEvidencePolicy.version,
        )
        #expect(grouped.count == 1)
        let issue = try #require(grouped.first)
        #expect(try issue.period == RecordingAssessmentTestSupport.period(0, 1200))
        #expect(issue.segments == [first, second])
        #expect(issue.days == .known([
            RecordingIssueTestSupport.firstDay,
            RecordingIssueTestSupport.secondDay,
        ]))
        #expect(issue.sampleIDs == [sampleID])
        #expect(issue.policyVersion == RecordingEvidencePolicy.version)
    }

    @Test func overlappingDuplicateDeliveryHasTheSameGroupsAndIdentity() throws {
        let first = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let nested = try RecordingIssueTestSupport.issue(start: 100, end: 200)
        let extending = try RecordingIssueTestSupport.issue(start: 500, end: 900)
        let original = try RecordingIssue.grouped(
            [first, nested, extending],
            version: RecordingEvidencePolicy.version,
        )
        let reordered = try RecordingIssue.grouped(
            [extending, first, nested, first],
            version: RecordingEvidencePolicy.version,
        )
        #expect(original == reordered)
        #expect(original.count == 1)
        #expect(original.first?.segments.count == 3)
        #expect(try original.first?.id.period == RecordingAssessmentTestSupport.period(0, 900))
    }

    @Test func aGapKeepsSeparateConcernsEvenOnTheSameLogicalDay() throws {
        let first = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let later = try RecordingIssueTestSupport.issue(start: 601, end: 1200)
        let result = try RecordingIssue.grouped(
            [later, first],
            version: RecordingEvidencePolicy.version,
        )
        #expect(result.map(\.period) == [first.period, later.period])
        #expect(result.map(\.segments) == [[first], [later]])
    }

    @Test func unknownAssignmentsStayUnknownWithoutLosingKnownCandidates() throws {
        let known = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let unknown = try RecordingIssueTestSupport.issue(
            start: 600,
            end: 1200,
            days: .unassigned(known: [RecordingIssueTestSupport.secondDay]),
        )
        let result = try RecordingIssue.grouped(
            [known, unknown],
            version: RecordingEvidencePolicy.version,
        )
        #expect(result.first?.days == .unassigned(known: [
            RecordingIssueTestSupport.firstDay,
            RecordingIssueTestSupport.secondDay,
        ]))
        #expect(result.first?.segments == [known, unknown])
    }

    @Test func equalBoundsRetainDistinctProblems() throws {
        let first = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let removed = try RecordingIssueTestSupport.issue(
            start: 0,
            end: 600,
            problem: .controls(.selectedDeviceRemoved(RecordingAssessmentTestSupport.first)),
        )
        let result = try RecordingIssue.grouped(
            [first, removed],
            version: RecordingEvidencePolicy.version,
        )
        #expect(result.first?.segments == [first, removed])
        #expect(result.count == 1)
    }

    @Test func compatiblePolicyChangesRefreshTheValueWithoutInventingANewScope() throws {
        let raw = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let original = try RecordingIssue.grouped(
            [raw],
            version: .init(major: 1, minor: 0, patch: 0),
        )
        let updated = try RecordingIssue.grouped(
            [raw],
            version: .init(major: 1, minor: 1, patch: 0),
        )
        #expect(original.map(\.id) == updated.map(\.id))
        #expect(original != updated)
        #expect(updated.first?.policyVersion == DataSemanticsVersion(major: 1, minor: 1, patch: 0))
    }

    @Test func invalidWirePeriodsFailInsteadOfDisappearing() throws {
        let period = try JSONDecoder().decode(
            RecordingPeriod.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        let issue = RecordingHistorySelection.Issue(
            period: period,
            problem: .recordingDay([RecordingAssessmentTestSupport.first]),
            days: .unassigned(known: []),
            sampleIDs: [],
        )
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try RecordingIssue.grouped([issue], version: RecordingEvidencePolicy.version)
        }
    }

    @Test func emptyHistoryHasNoRecordingConcerns() throws {
        #expect(try RecordingIssue.grouped([], version: RecordingEvidencePolicy.version).isEmpty)
    }
}
