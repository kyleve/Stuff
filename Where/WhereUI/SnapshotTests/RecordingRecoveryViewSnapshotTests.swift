import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingRecoveryViewSnapshotTests {
    @Test func recovery() async {
        await assertSnapshots(of: RecordingRecoveryView.self)
    }
}
