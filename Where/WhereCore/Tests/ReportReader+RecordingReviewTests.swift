import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct ReportReaderRecordingReviewTests {
    @Test func readsDisjointPeriodsWithAdjacentContextWithoutClaimingTheInterveningGap(
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [0.0, 10000].flatMap { offset in
            try [0.0, 600, 1200].flatMap { seconds in
                try [
                    LocationHistoryReaderTestSupport.sample(seconds: offset + seconds),
                    LocationHistoryReaderTestSupport.sample(
                        seconds: offset + seconds,
                        deviceID: RecordingAssessmentTestSupport.second,
                        longitude: -74,
                    ),
                ]
            }
        }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let first = try RecordingAssessmentTestSupport.period(100, 200)
        let second = try RecordingAssessmentTestSupport.period(10100, 10200)
        let snapshot = try await LocationHistoryReaderTestSupport.reports(store).recordingReview(
            periods: [second, first, first],
            scopeID: RecordingReviewTestSupport.scopeID,
        )
        #expect(snapshot.covers([first, second]))
        #expect(try snapshot.covers([RecordingAssessmentTestSupport.period(200, 10100)]) == false)
        #expect(snapshot.assessedPeriods.count == 2)
        #expect(snapshot.issues.count == 2)
        #expect(snapshot.issues[0].period.start < first.start)
        #expect(snapshot.issues[0].period.end > first.end)
        #expect(snapshot.generationID == .initial)
        #expect(snapshot.scopeID == RecordingReviewTestSupport.scopeID)
        #expect(snapshot.policyVersion == RecordingEvidencePolicy.version)
        #expect(Set(snapshot.issues.flatMap(\.sampleIDs)) == Set(samples.map(\.id)))
        #expect(try await Set(store.allSamples()) == Set(samples))
    }

    @Test func foundationAssessmentDoesNotActivateRecording() async throws {
        let store = try SwiftDataStore.inMemory()
        let calendar = LocationHistoryReaderTestSupport.calendar
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            attributor: RegionAttributor(for: []),
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
        )
        let snapshot = try await reader.recordingReview(
            periods: [RecordingAssessmentTestSupport.period(0, 1201)],
            scopeID: RecordingReviewTestSupport.scopeID,
        )
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.policyVersion == DataCompatibilityPolicy.foundation.current)
        #expect(try await store.dataContractMajor() == 0)
    }

    @Test func malformedInputCannotBecomeValidThroughContextPadding() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let invalid = try JSONDecoder().decode(
            RecordingPeriod.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        await #expect(throws: RecordingPeriod.ValidationError.self) {
            try await reader.recordingReview(
                periods: [invalid],
                scopeID: RecordingReviewTestSupport.scopeID,
            )
        }
        await #expect(throws: RecordingReviewSnapshot.ValidationError.emptyAssessment) {
            try await reader.recordingReview(
                periods: [],
                scopeID: RecordingReviewTestSupport.scopeID,
            )
        }
    }
}
