import Foundation
import Testing
@testable import WhereCore

struct DataIssueScanResultTests {
    @Test func recordingConcernsUseTheScansCompletenessEvenWithoutConventionalSuggestions() throws {
        let first = try RecordingIssueTestSupport.issue(start: 0, end: 600)
        let second = try RecordingIssueTestSupport.issue(start: 600, end: 1200)
        let completeness = HistoryCompleteness.recording(
            version: RecordingEvidencePolicy.version,
            days: CalendarDay.yearRange(2001),
            issues: [first, second],
        )
        let scan = DataIssueScanResult(
            revision: UUID(),
            completeness: completeness,
            issues: [],
            reviews: [],
            completedFlights: [],
            nextReassessmentAt: nil,
        )
        let recording = try scan.recordingIssues
        #expect(recording.count == 1)
        #expect(recording.first?.segments == [first, second])
        #expect(recording.first?.policyVersion == completeness.policyVersion)
        #expect(!scan.completeness.isComplete)
        #expect(scan.issues.isEmpty)
    }

    @Test func foundationScanDoesNotActivateRecordingIssues() throws {
        let scan = DataIssueScanResult(
            revision: UUID(),
            completeness: .foundation,
            issues: [],
            reviews: [],
            completedFlights: [],
            nextReassessmentAt: nil,
        )
        #expect(try scan.recordingIssues.isEmpty)
    }
}
