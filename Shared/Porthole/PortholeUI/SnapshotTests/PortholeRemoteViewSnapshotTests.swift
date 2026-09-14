import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeRemoteViewSnapshotTests {
    @Test func pairing() async {
        await assertSnapshots(of: PortholeRemoteView.self)
    }
}
