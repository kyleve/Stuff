import Foundation
@testable import WhereCore

enum RecordingControlSelectionTestSupport {
    static func snapshot(_ values: [RecordingControl]) throws -> RecordingControlSnapshot {
        try RecordingControlSnapshot(
            records: values.map { try RecordingControlCodec.encode($0, generationID: .initial) },
            generationID: .initial,
            policy: RecordingChoiceTestSupport.policy,
        )
    }

    static func removal(at seconds: Double, identity: Int = 100) -> RecordingDeviceRemoval {
        .init(
            id: .init(rawValue: RecordingAssessmentTestSupport.decisionID(identity).rawValue),
            deviceID: RecordingControlsTestSupport.device,
            removedAt: RecordingAssessmentTestSupport.time(seconds),
            removedByDeviceID: RecordingControlsTestSupport.otherDevice,
        )
    }

    static func resolve(
        _ controls: [RecordingControl],
        removals: [RecordingDeviceRemoval] = [],
        end: Double = 86400,
    ) throws -> [RecordingControlSelection.Segment] {
        try RecordingControlSelection.resolve(
            controls: snapshot(controls),
            removals: removals,
            within: RecordingAssessmentTestSupport.period(0, end),
            version: RecordingEvidencePolicy.version,
        )
    }
}
