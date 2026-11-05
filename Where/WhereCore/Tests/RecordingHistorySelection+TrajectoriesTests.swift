import Foundation
import Testing
@testable import WhereCore

struct RecordingHistorySelectionTrajectoriesTests {
    @Test func anUnknownDayOnAChosenSourceBreaksContinuity() throws {
        let device = RecordingAssessmentTestSupport.first
        let before = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let unknown = try RecordingAssessmentTestSupport.observation(
            seconds: 600,
            assignment: .unresolved,
        )
        let after = try RecordingAssessmentTestSupport.observation(seconds: 1200)
        let selection = try RecordingHistorySelectionTestSupport.resolve(
            [before, unknown, after],
            controls: [
                .source(RecordingAssessmentTestSupport.decision(960, end: 1201)),
            ],
        )
        #expect(selection.contributions == [before, after])
        #expect(try selection
            .trajectoryExclusions(for: device) == [RecordingAssessmentTestSupport.period(
                600,
                601,
            )])
    }

    @Test func automaticGapsDoNotBecomeExclusions() throws {
        let before = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let after = try RecordingAssessmentTestSupport.observation(seconds: 7200)
        let selection = try RecordingHistorySelectionTestSupport.resolve([before, after], end: 7201)
        #expect(selection.trajectoryExclusions(for: before.deviceID).isEmpty)
    }
}
