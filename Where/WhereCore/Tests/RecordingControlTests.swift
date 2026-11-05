import Testing
@testable import WhereCore

struct RecordingControlTests {
    @Test func envelopeIdentityAlwaysComesFromTheOperation() throws {
        let values: [RecordingControl] = try [
            .source(RecordingAssessmentTestSupport.decision(1)),
            .ignore(RecordingControlsTestSupport.ignore(2)),
            .place(RecordingControlsTestSupport.place(3)),
            .calendar(RecordingControlsTestSupport.calendar(4, action: .withdraw)),
        ]
        for (index, value) in values.enumerated() {
            try value.validate()
            #expect(value.recordID.rawValue == RecordingAssessmentTestSupport.decisionID(index + 1)
                .rawValue)
            #expect(value.version == RecordingControlsTestSupport.version)
        }
    }
}
