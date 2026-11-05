import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingReviewReaderTests {
    @Test func causalAncestorsOutsideThePeriodRemainRelevantButUnrelatedControlsDoNot(
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let ancestor = try RecordingAssessmentTestSupport.decision(70, start: 86400, end: 86500)
        let child = try RecordingAssessmentTestSupport.decision(71, predecessors: [ancestor.id])
        let unrelated = try RecordingAssessmentTestSupport.decision(72, start: 86400, end: 86500)
        try await RecordingChoiceTestSupport.append(.source(child), store: store)
        let reader = RecordingReviewReader(store: store, policy: RecordingChoiceTestSupport.policy)
        let request = try RecordingChoiceTestSupport.request()
        let missing = try await reader.evidence(for: request)
        try await RecordingChoiceTestSupport.append(.source(unrelated), store: store)
        #expect(try await reader.evidence(for: request) == missing)
        try await RecordingChoiceTestSupport.append(.source(ancestor), store: store)
        let complete = try await reader.evidence(for: request)
        #expect(complete != missing)
        #expect(Set(complete.controls.sourceChoices) == [ancestor, child])
    }

    @Test func correctionsManualOverlaysAndRelevantRemovalsInvalidateTheEvidence() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try RecordingChoiceTestSupport.sample(seconds: 50)
        try await store.perform { try await store.add(sample: sample) }
        let reader = RecordingReviewReader(store: store, policy: RecordingChoiceTestSupport.policy)
        let request = try RecordingChoiceTestSupport.request()
        let initial = try await reader.evidence(for: request)
        try await store.perform {
            try await store.addSampleAttributionRevision(.init(
                id: .init(rawValue: UUID()),
                sampleID: sample.id,
                updatedAt: sample.timestamp,
                replacementRegions: [],
            ))
        }
        let corrected = try await reader.evidence(for: request)
        #expect(corrected != initial)
        #expect(corrected.samples == initial.samples)
        try await store.perform {
            try await store.setManualDay(.init(
                day: CalendarDay(year: 2001, month: 1, day: 1),
                regions: [.california],
                isAuthoritative: true,
                audit: nil,
            ))
        }
        let manual = try await reader.evidence(for: request)
        #expect(manual != corrected)
        try await store.perform {
            try await store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: RecordingChoiceTestSupport.author,
                removedAt: sample.timestamp,
                removedByDeviceID: RecordingControlsTestSupport.otherDevice,
            ))
        }
        let removed = try await reader.evidence(for: request)
        #expect(removed != manual)
        #expect(removed.samples == initial.samples)
    }
}
