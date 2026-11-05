import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingPlaceViewSnapshotTests {
    @Test func recordingPlaceView() async {
        await assertSnapshots(of: RecordingPlaceView.self)
    }
}
