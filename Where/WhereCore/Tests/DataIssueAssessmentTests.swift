import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataIssueAssessmentTests {
    @Test func uncertainRecordingDatesBlockOnlyTheirPossibleMissingDays() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            [LocationHistoryReaderTestSupport.sample(seconds: 0, assignment: .unresolved)],
            to: store,
        )
        let reads = try await LocationHistoryReaderTestSupport.reports(store)
            .dataIssueReads(for: 2001)
        let result = try DataIssueAssessment(
            calendar: HistoricalDataIssueTestSupport.calendar,
            detectors: [MissingDaysDetector()],
        ).scan(
            reads: reads,
            driftThresholdMeters: 1000,
            now: HistoricalDataIssueTestSupport.now,
        )
        #expect(result.completeness.hasUnassignedDays)
        #expect(result.issues.compactMap { $0 as? MissingDaysIssue }.map(\.range.start)
            == [CalendarDay(year: 2001, month: 1, day: 2)])
        #expect(try result.recordingIssues.count == 1)
    }
}
