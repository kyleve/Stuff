import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct HistoricalDataIssueScanResultTests {
    @Test func continuousNewYearConflictIsCountedOnceAndKeepsBothYearContexts() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try HistoricalDataIssueTestSupport.conflicts(at: [-600, 0, 600])
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let reads = try await LocationHistoryReaderTestSupport.reports(store)
            .historicalDataIssueReads(currentYear: 2002)
        let result = try HistoricalDataIssueTestSupport.result(reads)
        #expect(result.recording.issues.count == 1)
        let issue = try #require(result.recording.issues.first)
        #expect(issue.days == .known([
            CalendarDay(year: 2000, month: 12, day: 31),
            CalendarDay(year: 2001, month: 1, day: 1),
        ]))
        let references = try result.references(for: issue)
        #expect(Set(references.map(\.context.historicalYear)) == [2000, 2001])
        let queue = try RecordingReviewQueue(references: Array(references))
        #expect(queue.originalPeriods == [issue.period])
        let remaining = try queue.remaining(in: result.recording)
        #expect(remaining.count == 1)
        #expect(try await Set(store.allSamples()) == Set(samples))
    }

    @Test func unassignedObservationsDoNotBridgeUnassessedGaps() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [0.0, 600, 7200, 7800].map {
            try LocationHistoryReaderTestSupport.sample(seconds: $0, assignment: .unresolved)
        }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let reads = try await LocationHistoryReaderTestSupport.reports(store)
            .historicalDataIssueReads(currentYear: 2002)
        let result = try HistoricalDataIssueTestSupport.result(reads)
        // One available source with an unknown day contributes point-supported review periods.
        // Its silent intervals cannot become calendar evidence through grouping.
        let expected = try [0.0, 600, 7200, 7800].map {
            try RecordingAssessmentTestSupport.period($0, $0 + RecordingEvidencePolicy.pointSupport)
        }
        #expect(result.recording.issues.map(\.period) == expected)
        #expect(result.recording.issues.allSatisfy { $0.days == .unassigned(known: []) })
        let references = try result.recording.issues.reduce(into: Set<RecordingReviewReference>()) {
            try $0.formUnion(result.references(for: $1))
        }
        let queue = try RecordingReviewQueue(references: Array(references))
        #expect(queue.originalPeriods == expected)
    }

    @Test func mismatchedGenerationCannotBecomeOnePublication() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let before = try await reader.historicalDataIssueReads(currentYear: 2001)
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingAssessmentTestSupport.first,
                at: HistoricalDataIssueTestSupport.now,
            )
        }
        let after = try await reader.historicalDataIssueReads(currentYear: 2002)
        #expect(throws: DataCompatibilityError.concurrentChange) {
            try HistoricalDataIssueTestSupport.result(.init(
                generationID: before.generationID,
                years: before.years + after.years,
            ))
        }
    }

    @Test func mismatchedPoliciesCannotBecomeOnePublication() async throws {
        let recording = try await RecordingChoiceTestSupport.store()
        let foundation = try SwiftDataStore.inMemory()
        let first = try await LocationHistoryReaderTestSupport.reports(recording)
            .historicalDataIssueReads(currentYear: 2001)
        let reader = ReportReader(
            store: foundation,
            aggregator: DayAggregator(
                calendar: HistoricalDataIssueTestSupport.calendar,
                timeZone: .gmt,
            ),
            attributor: RegionAttributor(for: []),
            history: LocationHistoryReader(
                store: foundation,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
        )
        let second = try await reader.historicalDataIssueReads(currentYear: 2002)
        #expect(throws: DataCompatibilityError.concurrentChange) {
            try HistoricalDataIssueTestSupport.result(.init(
                generationID: first.generationID,
                years: first.years + second.years,
            ))
        }
        let foundationResult = try HistoricalDataIssueTestSupport.result(second)
        let context = try #require(second.years.first?.context)
        #expect(try foundationResult.recording.assessedPeriods == [
            context.query.viewingPeriod(in: HistoricalDataIssueTestSupport.calendar),
        ])
    }

    @Test func unassessedQueryCannotBecomeCovered() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let reads = try await LocationHistoryReaderTestSupport.reports(store)
            .historicalDataIssueReads(currentYear: 2001)
        let year = try #require(reads.years.first)
        #expect(throws: HistoryCompleteness.ValidationError.outsideAssessedScope) {
            try HistoricalDataIssueTestSupport.result(.init(
                generationID: reads.generationID,
                years: [.init(
                    context: .init(
                        historicalYear: 2001,
                        query: .days(CalendarDay(year: 1999, month: 1, day: 1)
                            ... CalendarDay(year: 2002, month: 12, day: 31)),
                    ),
                    reads: year.reads,
                )],
            ))
        }
    }
}
