import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingHistoryViewSnapshotTests {
    @Test func recordingHistoryView() async {
        await assertSnapshots(of: RecordingHistoryView.self)
    }
}
