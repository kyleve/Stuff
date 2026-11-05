import Foundation
import Testing
@testable import WhereCore

struct RecordingReviewNotificationTests {
    @Test func relaunchRetainsOriginalYearQueryAndBoundsAcrossSplitAndMerge() throws {
        let initial = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 300),
            RecordingIssueTestSupport.issue(start: 500, end: 700),
        ])
        let references = try [
            RecordingReviewTestSupport.reference(initial, historicalYear: 2000),
            RecordingReviewTestSupport.reference(initial, issueIndex: 1, historicalYear: 2001),
        ]
        let saved = try RecordingReviewNotification(references: references, binding: binding)
        let decoded = try JSONDecoder().decode(
            RecordingReviewNotification.self,
            from: JSONEncoder().encode(saved),
        )
        #expect(decoded == saved)
        let freshScope = RecordingReviewSnapshot.ScopeID(rawValue: UUID())
        let merged = try RecordingReviewTestSupport.snapshot(
            [RecordingIssueTestSupport.issue(start: 0, end: 900)],
            scopeID: freshScope,
            version: .init(major: 1, minor: 3, patch: 7),
        )
        let restored = try decoded.restore(binding: binding, snapshot: merged)
        let item = try #require(restored.remaining(in: merged).first)
        #expect(item.periods == saved.originalPeriods)
        #expect(item.periods.count == 2)
        #expect(Set(item.references.map(\.context)) == Set(references.map(\.context)))
        #expect(Set(item.references.map(\.issueID)) == Set(references.map(\.issueID)))
        #expect(item.references.allSatisfy { $0.scopeID == freshScope })
        let split = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 150, end: 250),
            RecordingIssueTestSupport.issue(start: 550, end: 650),
            RecordingIssueTestSupport.issue(start: 1000, end: 1500),
        ], scopeID: freshScope)
        #expect(try restored.remaining(in: split).map(\.periods) == [
            [RecordingAssessmentTestSupport.period(150, 250)],
            [RecordingAssessmentTestSupport.period(550, 650)],
        ])
    }

    @Test func accountContainerStoreAndLocalModeAreAllPartOfTheBinding() throws {
        let initial = try snapshot()
        let saved = try notification(initial)
        let otherBindings: [RecordingReviewNotification.Binding] = [
            .cloudKit(
                storeID: .init(rawValue: "other"),
                containerIdentifier: "container",
                accountID: .init(rawValue: "account"),
            ),
            .cloudKit(
                storeID: .init(rawValue: "store"),
                containerIdentifier: "other",
                accountID: .init(rawValue: "account"),
            ),
            .cloudKit(
                storeID: .init(rawValue: "store"),
                containerIdentifier: "container",
                accountID: .init(rawValue: "other"),
            ),
            .local(storeID: .init(rawValue: "store")),
        ]
        for other in otherBindings {
            #expect(throws: RecordingReviewNotification.ValidationError.differentDataset) {
                try saved.restore(binding: other, snapshot: initial)
            }
        }
    }

    @Test func resetIncompatibleMajorAndPartialAssessmentCannotClaimResolution() throws {
        let initial = try snapshot()
        let saved = try notification(initial)
        let reset = try RecordingReviewTestSupport.snapshot(
            [],
            generationID: .init(rawValue: UUID()),
        )
        #expect(throws: RecordingReviewQueue.ValidationError.dataGenerationChanged) {
            try saved.restore(binding: binding, snapshot: reset)
        }
        let incompatible = try RecordingReviewTestSupport.snapshot(
            [],
            version: .init(major: 2, minor: 0, patch: 0),
        )
        #expect(throws: RecordingReviewQueue.ValidationError.incompatiblePolicy) {
            try saved.restore(binding: binding, snapshot: incompatible)
        }
        let partial = try RecordingReviewTestSupport.snapshot(
            [],
            periods: [RecordingAssessmentTestSupport.period(100, 200)],
        )
        #expect(throws: RecordingReviewQueue.ValidationError.incompleteAssessment) {
            try saved.restore(binding: binding, snapshot: partial)
        }
        let resolved = try RecordingReviewTestSupport.snapshot([], scopeID: .init(rawValue: UUID()))
        #expect(try saved.restore(binding: binding, snapshot: resolved).remaining(in: resolved)
            .isEmpty)
        #expect(try saved.restore(binding: binding, snapshot: initial).remaining(in: initial)
            .count == 1)
    }

    @Test func logicalDateQuerySurvivesSerializationWithoutUsingTheViewingZone() throws {
        let initial = try snapshot()
        let reference = try RecordingReviewTestSupport.reference(
            initial,
            query: .days(CalendarDay.yearRange(2001)),
        )
        let saved = try RecordingReviewNotification(references: [reference], binding: binding)
        let decoded = try JSONDecoder().decode(
            RecordingReviewNotification.self,
            from: JSONEncoder().encode(saved),
        )
        #expect(decoded.references.first?.context == reference.context)
        #expect(try decoded.restore(binding: binding, snapshot: initial)
            .originalPeriods == reference.originalPeriods)
    }

    @Test func decodedFutureFormatAndMalformedScopeAreRejected() throws {
        let saved = try notification(snapshot())
        let data = try JSONEncoder().encode(saved)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 2
        let future = try JSONDecoder().decode(
            RecordingReviewNotification.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
        #expect(throws: RecordingReviewNotification.ValidationError.unsupportedFormat) {
            try future.validate()
        }
        object["formatVersion"] = 1
        var references = try #require(object["references"] as? [[String: Any]])
        references[0]["originalPeriods"] = [["start": 250, "end": 100]]
        object["references"] = references
        let malformed = try JSONDecoder().decode(
            RecordingReviewNotification.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
        #expect(throws: RecordingPeriod.ValidationError.self) { try malformed.validate() }
    }

    private var binding: RecordingReviewNotification.Binding {
        .cloudKit(
            storeID: .init(rawValue: "store"),
            containerIdentifier: "container",
            accountID: .init(rawValue: "account"),
        )
    }

    private func snapshot() throws -> RecordingReviewSnapshot {
        try RecordingReviewTestSupport.snapshot([RecordingIssueTestSupport.issue(
            start: 100,
            end: 300,
        )])
    }

    private func notification(_ snapshot: RecordingReviewSnapshot) throws
        -> RecordingReviewNotification
    {
        try RecordingReviewNotification(
            references: [RecordingReviewTestSupport.reference(snapshot)],
            binding: binding,
        )
    }
}
