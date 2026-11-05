import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

enum RecordingReviewTestSupport {
    static let scopeID = RecordingReviewSnapshot.ScopeID(rawValue: UUID(
        uuidString: "00000000-0000-0000-0000-000000000901",
    )!)

    static func scanner(_ store: any WhereStore) -> DataIssueScanner {
        DataIssueScanner(
            reportReader: LocationHistoryReaderTestSupport.reports(store),
            attributor: RegionAttributor(for: []),
            calendar: LocationHistoryReaderTestSupport.calendar,
        )
    }

    static func queue(_ scanner: DataIssueScanner) async throws -> RecordingReviewQueue {
        let period = try RecordingAssessmentTestSupport.period(0, 1201)
        let snapshot = try await scanner.recordingReview(periods: [period])
        return try RecordingReviewQueue(references: [reference(
            snapshot,
            periods: [period],
            query: .instants(period),
        )])
    }

    static func snapshot(
        _ issues: [RecordingHistorySelection.Issue],
        periods: [RecordingPeriod]? = nil,
        scopeID: RecordingReviewSnapshot.ScopeID = scopeID,
        generationID: WhereDataGenerationID = .initial,
        version: DataSemanticsVersion = RecordingEvidencePolicy.version,
    ) throws -> RecordingReviewSnapshot {
        try RecordingReviewSnapshot(
            scopeID: scopeID,
            generationID: generationID,
            policyVersion: version,
            assessedPeriods: periods ?? [RecordingAssessmentTestSupport.period(0, 3600)],
            issues: issues,
        )
    }

    static func reference(
        _ snapshot: RecordingReviewSnapshot,
        issueIndex: Int = 0,
        periods: [RecordingPeriod]? = nil,
        historicalYear: Int = 2001,
        query: LocationHistoryQuery? = nil,
    ) throws -> RecordingReviewReference {
        try #require(snapshot.issues.indices.contains(issueIndex))
        let issue = snapshot.issues[issueIndex]
        return try RecordingReviewReference(
            issue: issue,
            originalPeriods: periods ?? [issue.period],
            context: .init(
                historicalYear: historicalYear,
                query: query ?? .instants(RecordingAssessmentTestSupport.period(0, 3600)),
            ),
            snapshot: snapshot,
        )
    }
}
