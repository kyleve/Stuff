import Foundation
import Testing
@testable import WhereCore

struct RecordingControlEditTests {
    @Test func resumeKeepsItsCutoffAndRejectsExpiredOrRestoredDecisions() throws {
        let decision = try RecordingControlsTestSupport.ignore(1)
        let cutoff = Date(timeIntervalSinceReferenceDate: 600)
        let resume = try RecordingControlEdit.resumingIgnore(decision, at: cutoff)
        #expect(try resume.query().periods == [RecordingAssessmentTestSupport.period(600, 86400)])
        #expect(throws: RecordingControlEdit.ValidationError.ignoreAlreadyEnded) {
            try RecordingControlEdit.resumingIgnore(
                decision,
                at: .init(timeIntervalSinceReferenceDate: 86400),
            )
        }
        let restored = try RecordingControlsTestSupport.ignore(2, change: .restoreEligibility)
        #expect(throws: RecordingControlEdit.ValidationError.notAnIgnore) {
            try RecordingControlEdit.resumingIgnore(restored, at: cutoff)
        }
    }

    @Test func anEditCannotAdoptAnotherDevicesCalendarOrIgnoreHistory() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let other = try RecordingControlsTestSupport.calendar(
            45,
            action: .withdraw,
            deviceID: RecordingControlsTestSupport.otherDevice,
        )
        try await RecordingChoiceTestSupport.append(.calendar(other), store: store)
        let edit = try RecordingControlEditTestSupport.edit(.calendar, removes: false)
        let evidence = try await RecordingReviewReader(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        ).evidence(for: edit.query())
        let operation = try edit.prepare(
            operationID: UUID(),
            author: RecordingChoiceTestSupport.author,
            evidence: evidence,
        )
        #expect(operation.predecessorRecordIDs.isEmpty)
        let malformed = try RecordingControlEdit.calendar(
            deviceID: RecordingChoiceTestSupport.author,
            periods: RecordingControlsTestSupport.malformedPeriods(),
            action: .withdraw,
        )
        #expect(throws: (any Error).self) { try malformed.query() }
    }
}
