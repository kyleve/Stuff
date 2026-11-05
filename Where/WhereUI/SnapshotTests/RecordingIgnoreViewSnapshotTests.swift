import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingIgnoreViewSnapshotTests {
    @Test func recordingIgnore() async {
        await assertSnapshots(of: RecordingIgnoreView.self)
    }
}
