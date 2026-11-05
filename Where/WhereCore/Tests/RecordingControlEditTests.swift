import Foundation
import Testing
@testable import WhereCore

struct RecordingControlEditTests {
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
