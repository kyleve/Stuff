import Foundation
import RegionKit
@_spi(Testing) @testable import WhereCore

/// Supplies deterministic ordinary issues through the production detector and scan boundaries.
enum DataIssueReviewQueueTestSupport {
    struct Detector: DataIssueDetecting {
        let detects: DataIssueCategory
        let issues: [any DataIssue]
        func detectAnyIssues(in _: DataIssueInput) throws -> [any DataIssue] {
            issues
        }
    }

    static func snapshot(
        _ issues: [any DataIssue],
        year: Int = 2001,
        scopeID: RecordingReviewSnapshot.ScopeID = RecordingReviewTestSupport.scopeID,
        store: SwiftDataStore? = nil,
        policy: DataCompatibilityPolicy = RecordingChoiceTestSupport.policy,
    ) async throws -> HistoricalDataIssueScanResult {
        let source: SwiftDataStore = if let store { store }
        else { try await RecordingChoiceTestSupport.store() }
        let calendar = HistoricalDataIssueTestSupport.calendar
        let reader = ReportReader(
            store: source,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            attributor: RegionAttributor(for: []),
            history: LocationHistoryReader(
                store: source,
                policy: policy,
                geography: HistoryRegionAttribution(catalog: LocationHistoryReaderTestSupport
                    .Geography()),
            ),
        )
        let reads = try await reader.historicalDataIssueReads(currentYear: year)
        return try HistoricalDataIssueScanResult(
            reads: reads,
            scopeID: scopeID,
            assessment: DataIssueAssessment(
                calendar: HistoricalDataIssueTestSupport.calendar,
                detectors: DataIssueCategory.allCases.map { category in
                    Detector(detects: category, issues: issues.filter { $0.category == category })
                },
            ),
            driftThresholdMeters: 1000,
            now: HistoricalDataIssueTestSupport.now,
        )
    }

    static func day(_ value: Int) -> CalendarDay {
        CalendarDay(year: 2001, month: 1, day: value)
    }

    static func missing(_ first: Int, _ last: Int) -> MissingDaysIssue {
        MissingDaysIssue(range: .init(
            start: day(first),
            end: day(last),
            dayCount: last - first + 1,
        ))
    }
}
