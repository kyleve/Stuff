import Testing
@testable import WhereCore

enum RecordingChoiceInspectionTestSupport {
    static func request(
        start: Double = 0,
        end: Double = 1201,
        action: HistoryDecision.Action = .select(RecordingAssessmentTestSupport.first),
    ) throws -> RecordingChoiceRequest {
        try .init(
            scope: .periods([RecordingAssessmentTestSupport.period(start, end)]),
            action: action,
        )
    }

    static func preview(_ inspection: RecordingChoiceInspection) throws
        -> RecordingChoiceInspection.Preview
    {
        guard case let .ready(preview) = inspection else {
            throw RecordingChoiceTestSupport.TestError.expectedProposal
        }
        return preview
    }
}
