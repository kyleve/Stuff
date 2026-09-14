import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeHostingViewSnapshotTests {
    @Test func activationAndEnrollment() async {
        await assertSnapshots(of: PortholeHostingView.self)
    }
}
