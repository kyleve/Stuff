import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingReviewFlowViewSnapshotTests {
    @Test func recordingReviewFlow() async {
        await assertSnapshots(of: RecordingReviewFlowView.self)
    }
}
