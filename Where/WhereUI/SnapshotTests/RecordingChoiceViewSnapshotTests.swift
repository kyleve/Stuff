import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingChoiceViewSnapshotTests {
    @Test func recordingChoice() async {
        await assertSnapshots(of: RecordingChoiceView.self)
    }
}
