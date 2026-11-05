import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingIgnoreInspectionTests {
    @Test func newIgnorePreviewUsesTheExactReviewedEvidenceUntilAStaleApply() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let proposal = try await coordinator.review(RecordingControlEditTestSupport.edit(
            .ignore,
            removes: false,
        ))
        let preview = try coordinator.inspectIgnore(proposal)
        #expect(preview.deviceID == RecordingControlsTestSupport.device)
        #expect(preview.changes.count == 1)
        #expect(preview.changes[0].before == .automatic(.eligible))
        #expect(preview.changes[0].after == .automatic(.ignored))
        #expect(try preview.changes[0].period == RecordingAssessmentTestSupport.period(0, 86400))
        #expect(try await store.versionedHistoryRecords(policy: RecordingChoiceTestSupport.policy)
            .isEmpty)

        let source = try RecordingAssessmentTestSupport.decision(10, start: 100, end: 200)
        try await RecordingChoiceTestSupport.append(.source(source), store: store)
        #expect(try coordinator.inspectIgnore(proposal) == preview)
        guard case let .stale(refreshed) = try await coordinator.apply(proposal) else {
            Issue.record("New source evidence must refresh the proposal before saving.")
            return
        }
        let updated = try coordinator.inspectIgnore(refreshed)
        #expect(updated.changes.count == 3)
        #expect(updated.changes[1].before == .selected(source.author))
        #expect(updated.changes[1].after == .selected(source.author))
        #expect(try await coordinator.ignoreHistory(for: source.author).decisions.isEmpty)
    }

    @Test func shorteningShowsRestoredTailAndPreservesExplicitSourcesAndRemoval() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.ignore(
            1,
            end: 259_200,
            change: .ignore(.init(day: .init(year: 2001, month: 1, day: 3), timeZone: .gmt)),
        )
        try await RecordingChoiceTestSupport.append(.ignore(original), store: store)
        let source = try RecordingAssessmentTestSupport.decision(10, start: 90000, end: 100_000)
        try await RecordingChoiceTestSupport.append(.source(source), store: store)
        let removal = RecordingControlSelectionTestSupport.removal(at: 200_000)
        try await store.perform { try await store.addRecordingDeviceRemoval(removal) }
        let proposal = try await coordinator.review(.changingIgnoreEnd(
            of: original,
            until: .init(day: .init(year: 2001, month: 1, day: 1), timeZone: .gmt),
        ))
        let preview = try coordinator.inspectIgnore(proposal)
        #expect(try preview.changes.map(\.period) == [
            RecordingAssessmentTestSupport.period(0, 86400),
            RecordingAssessmentTestSupport.period(86400, 90000),
            RecordingAssessmentTestSupport.period(90000, 100_000),
            RecordingAssessmentTestSupport.period(100_000, 200_000),
            RecordingAssessmentTestSupport.period(200_000, 259_200),
        ])
        #expect(preview.changes.map(\.before) == [
            .automatic(.ignored),
            .automatic(.ignored),
            .selected(source.author),
            .automatic(.ignored),
            .automatic(.removed),
        ])
        #expect(preview.changes.map(\.after) == [
            .automatic(.ignored),
            .automatic(.eligible),
            .selected(source.author),
            .automatic(.eligible),
            .automatic(.removed),
        ])
        #expect(try await coordinator.apply(proposal) == .applied)
        let history = try await coordinator.ignoreHistory(for: original.deviceID)
        #expect(history.decisions.count == 2)
        #expect(history.segments.map(\.resolution) == [.ignored, .eligible])
    }

    @Test func previewRetainsUnknownControlsAndSourceConflicts() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let first = try RecordingAssessmentTestSupport.decision(10, start: 100, end: 300)
        let second = try RecordingAssessmentTestSupport.decision(
            11,
            start: 100,
            end: 300,
            action: .select(RecordingControlsTestSupport.otherDevice),
        )
        try await RecordingChoiceTestSupport.append(.source(first), store: store)
        try await RecordingChoiceTestSupport.append(.source(second), store: store)
        let opaque = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport.period(400, 500)]),
            kind: "recording.future-control",
            payload: Data([1]),
        )
        try await store.perform { try await store.addVersionedHistoryRecord(opaque) }
        let proposal = try await coordinator.review(RecordingControlEditTestSupport.edit(
            .ignore,
            removes: false,
        ))
        let preview = try coordinator.inspectIgnore(proposal)
        #expect(preview.changes[1].before == .unresolved(.sourceConflict([first.id, second.id])))
        #expect(preview.changes[1].after == preview.changes[1].before)
        #expect(preview.changes[3].before == .unresolved(.unknownControls([opaque.id])))
        #expect(preview.changes[3].after == preview.changes[3].before)
        #expect(preview.changes.count(where: { $0.before != $0.after }) == 3)
    }

    @Test func separateUndoPeriodsKeepTheirGapsAndOtherDevicesIntact() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let original = try RecordingControlsTestSupport.ignore(1)
        let other = try RecordingControlsTestSupport.ignore(
            2,
            deviceID: RecordingControlsTestSupport.otherDevice,
        )
        try await RecordingChoiceTestSupport.append(.ignore(original), store: store)
        try await RecordingChoiceTestSupport.append(.ignore(other), store: store)
        let periods = try [
            RecordingAssessmentTestSupport.period(100, 200),
            RecordingAssessmentTestSupport.period(400, 500),
        ]
        let proposal = try await coordinator.review(.ignore(
            deviceID: original.deviceID,
            periods: periods,
            change: .restoreEligibility,
        ))
        let preview = try coordinator.inspectIgnore(proposal)
        #expect(preview.changes.map(\.period) == periods)
        #expect(preview.changes.allSatisfy {
            $0.before == .automatic(.ignored) && $0.after == .automatic(.eligible)
        })
        #expect(try await coordinator.apply(proposal) == .applied)
        let history = try await coordinator.ignoreHistory(for: original.deviceID)
        #expect(history.segments.map(\.resolution) == [
            .ignored,
            .eligible,
            .ignored,
            .eligible,
            .ignored,
        ])
        #expect(try await coordinator.ignoreHistory(for: other.deviceID).decisions == [other])
    }

    @Test func inspectionRejectsOtherControlFamiliesOrSeveralDevices() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingControlEditTestSupport.coordinator(store: store)
        let calendar = try await coordinator.review(RecordingControlEditTestSupport.edit(
            .calendar,
            removes: false,
        ))
        #expect(throws: RecordingIgnoreInspection.ValidationError.notAnIgnore) {
            try coordinator.inspectIgnore(calendar)
        }
        let first = try RecordingControlEditTestSupport.edit(.ignore, removes: false)
        let other = try RecordingControlEdit.ignore(
            deviceID: RecordingControlsTestSupport.otherDevice,
            periods: [RecordingAssessmentTestSupport.period(0, 86400)],
            change: .restoreEligibility,
        )
        let batch = try await coordinator.review([first, other])
        #expect(throws: RecordingIgnoreInspection.ValidationError.multipleDevices) {
            try coordinator.inspectIgnore(batch)
        }
    }
}
