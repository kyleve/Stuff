import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct DataIssueReviewQueueTests {
    @Test func splitAndMergedMissingRangesRetainOnlyOriginalDays() async throws {
        let originals = [
            DataIssueReviewQueueTestSupport.missing(3, 5),
            DataIssueReviewQueueTestSupport.missing(8, 9),
        ]
        let initial = try await DataIssueReviewQueueTestSupport.snapshot(originals)
        let queue = try DataIssueReviewQueue(issues: originals, snapshot: initial)
        let merged = try await DataIssueReviewQueueTestSupport
            .snapshot([DataIssueReviewQueueTestSupport.missing(
                1,
                12,
            )])
        let item = try #require(queue.remaining(in: merged).first)
        #expect(item.reviewDays == Set([3, 4, 5, 8, 9].map(DataIssueReviewQueueTestSupport.day)))
        #expect(item.references.count == 2)
        #expect(MissingDays.ranges(Array(item.reviewDays)).count == 2)
        let split = try await DataIssueReviewQueueTestSupport.snapshot([
            DataIssueReviewQueueTestSupport.missing(4, 4),
            DataIssueReviewQueueTestSupport.missing(
                8,
                8,
            ),
            DataIssueReviewQueueTestSupport.missing(20, 21),
        ])
        let remaining = try queue.remaining(in: split)
        #expect(remaining.map(\.reviewDays) == [
            [DataIssueReviewQueueTestSupport.day(4)],
            [DataIssueReviewQueueTestSupport.day(8)],
        ])
        let resolved = try await DataIssueReviewQueueTestSupport.snapshot([])
        #expect(try queue.remaining(in: resolved).isEmpty)
    }

    @Test func overlappingReferencesDoNotDuplicateCurrentWork() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let snapshot = try await DataIssueReviewQueueTestSupport.snapshot([issue])
        let queue = try DataIssueReviewQueue(issues: [issue, issue], snapshot: snapshot)
        #expect(queue.references.count == 1)
        #expect(try queue.remaining(in: snapshot).count == 1)
        let reference = try #require(queue.references.first)
        let restored = try JSONDecoder().decode(
            DataIssueReviewQueue.Reference.self,
            from: JSONEncoder().encode(reference),
        )
        try restored.validate()
        #expect(restored == reference)
        #expect(restored.context.historicalYear == 2001)
    }

    @Test func mergedTravelContextCannotExpandActionableDays() async throws {
        let original = AbruptChangeIssue(
            earlierDay: .init(day: DataIssueReviewQueueTestSupport.day(3), regions: [.newYork]),
            laterDay: .init(day: DataIssueReviewQueueTestSupport.day(4), regions: [.california]),
        )
        let snapshot = try await DataIssueReviewQueueTestSupport.snapshot([original])
        let queue = try DataIssueReviewQueue(issues: [original], snapshot: snapshot)
        let changed = AbruptChangeIssue(
            earlierDay: .init(day: DataIssueReviewQueueTestSupport.day(4), regions: [.newYork]),
            laterDay: .init(day: DataIssueReviewQueueTestSupport.day(5), regions: [.california]),
        )
        let fresh = try await DataIssueReviewQueueTestSupport.snapshot([
            changed,
            DataIssueReviewQueueTestSupport.missing(3, 5),
        ])
        let items = try queue.remaining(in: fresh)
        #expect(items.count == 1)
        #expect(items.first?.issue.id == changed.id)
        #expect(items.first?.reviewDays == [DataIssueReviewQueueTestSupport.day(4)])
    }

    @Test func missingOriginalYearAndDifferentScopeCannotClaimResolution() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let initial = try await DataIssueReviewQueueTestSupport.snapshot([issue])
        let queue = try DataIssueReviewQueue(issues: [issue], snapshot: initial)
        let laterYear = try await DataIssueReviewQueueTestSupport.snapshot([], year: 2002)
        #expect(throws: DataIssueReviewQueue.ValidationError.incompleteAssessment) {
            try queue.remaining(in: laterYear)
        }
        let differentScope = try await DataIssueReviewQueueTestSupport.snapshot(
            [],
            scopeID: .init(rawValue: UUID()),
        )
        #expect(throws: DataIssueReviewQueue.ValidationError.differentServiceScope) {
            try queue.remaining(in: differentScope)
        }
    }

    @Test func resetAndFoundationHistoryCannotReuseRecordingDayWork() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let store = try await RecordingChoiceTestSupport.store()
        let initial = try await DataIssueReviewQueueTestSupport.snapshot([issue], store: store)
        let queue = try DataIssueReviewQueue(issues: [issue], snapshot: initial)
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: RecordingAssessmentTestSupport.first,
                at: HistoricalDataIssueTestSupport.now,
            )
        }
        let reset = try await DataIssueReviewQueueTestSupport.snapshot([], store: store)
        #expect(throws: DataIssueReviewQueue.ValidationError.dataGenerationChanged) {
            try queue.remaining(in: reset)
        }
        let foundation = try await DataIssueReviewQueueTestSupport.snapshot(
            [issue],
            store: SwiftDataStore.inMemory(),
            policy: .foundation,
        )
        #expect(throws: DataIssueReviewQueue.ValidationError.unsupportedPolicy) {
            try DataIssueReviewQueue(issues: [issue], snapshot: foundation)
        }
        #expect(throws: DataIssueReviewQueue.ValidationError.incompatiblePolicy) {
            try queue.remaining(in: foundation)
        }
    }

    @Test func compatibleMinorPolicyCanReassessTheOriginalScope() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let initial = try await DataIssueReviewQueueTestSupport.snapshot([issue])
        let queue = try DataIssueReviewQueue(issues: [issue], snapshot: initial)
        let version = DataSemanticsVersion(major: 1, minor: 2, patch: 3)
        // Model a future build's successful assessment, without claiming this build can
        // execute that future resolver algorithm.
        let fresh = try HistoricalDataIssueScanResult(
            yearScans: [2001: DataIssueScanResult(
                revision: UUID(),
                completeness: .recording(
                    version: version,
                    days: CalendarDay.yearRange(2001),
                    issues: [],
                ),
                issues: [issue],
                reviews: [],
                completedFlights: [],
                nextReassessmentAt: nil,
            )],
            calendar: HistoricalDataIssueTestSupport.calendar,
            scopeID: initial.recording.scopeID,
            generationID: initial.recording.generationID,
        )
        #expect(fresh.recording.policyVersion == version)
        #expect(try queue.remaining(in: fresh).count == 1)
        #expect(queue.policyVersion == initial.recording.policyVersion)
    }

    @Test func decodedReferencesMustKeepTheirOriginalIdentityAndCategory() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let snapshot = try await DataIssueReviewQueueTestSupport.snapshot([issue])
        let queue = try DataIssueReviewQueue(issues: [issue], snapshot: snapshot)
        let reference = try #require(queue.references.first)
        let data = try JSONEncoder().encode(reference)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["category"] = DataIssueCategory.flightDay.rawValue
        let decoded = try JSONDecoder().decode(
            DataIssueReviewQueue.Reference.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
        #expect(throws: DataIssueReviewQueue.ValidationError.invalidScope) {
            try decoded.validate()
        }
    }

    @Test func unknownOrMalformedOriginalWorkIsRejected() async throws {
        let issue = DataIssueReviewQueueTestSupport.missing(3, 5)
        let snapshot = try await DataIssueReviewQueueTestSupport.snapshot([issue])
        #expect(throws: DataIssueReviewQueue.ValidationError.unknownIssue) {
            try DataIssueReviewQueue(
                issues: [DataIssueReviewQueueTestSupport.missing(3, 8)],
                snapshot: snapshot,
            )
        }
        let invalid = MissingDaysIssue(range: .init(
            start: DataIssueReviewQueueTestSupport.day(3),
            end: DataIssueReviewQueueTestSupport.day(5),
            dayCount: 99,
        ))
        let malformed = try await DataIssueReviewQueueTestSupport.snapshot([invalid])
        #expect(throws: DataIssueReviewQueue.ValidationError.invalidScope) {
            try DataIssueReviewQueue(issues: [invalid], snapshot: malformed)
        }
    }
}
