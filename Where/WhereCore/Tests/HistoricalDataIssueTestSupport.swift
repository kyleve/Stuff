import Foundation
import RegionKit
@_spi(Testing) @testable import WhereCore

enum HistoricalDataIssueTestSupport {
    static let calendar = LocationHistoryReaderTestSupport.calendar
    static let now = WhereCoreTestSupport.iso("2002-01-05T12:00:00Z")

    static func scanner(
        _ store: any WhereStore,
        now: @escaping @Sendable () -> Date = { HistoricalDataIssueTestSupport.now },
        changes: AsyncStream<Void> = AsyncStream { $0.finish() },
    ) -> DataIssueScanner {
        DataIssueScanner(
            reportReader: LocationHistoryReaderTestSupport.reports(store),
            attributor: RegionAttributor(for: []),
            calendar: calendar,
            now: now,
            storeChanges: changes,
        )
    }

    static func conflicts(at seconds: [Double]) throws -> [LocationSample] {
        try seconds.flatMap { second in
            try [
                LocationHistoryReaderTestSupport.sample(seconds: second, longitude: -122),
                LocationHistoryReaderTestSupport.sample(
                    seconds: second,
                    deviceID: RecordingAssessmentTestSupport.second,
                    longitude: -74,
                ),
            ]
        }
    }

    static func result(_ reads: HistoricalDataIssueReads) throws -> HistoricalDataIssueScanResult {
        try HistoricalDataIssueScanResult(
            reads: reads,
            scopeID: RecordingReviewTestSupport.scopeID,
            assessment: DataIssueAssessment(
                calendar: calendar,
                detectors: [MissingDaysDetector(), AbruptLocationChangeDetector()],
            ),
            driftThresholdMeters: 1000,
            now: now,
        )
    }
}
