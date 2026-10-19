@testable import InstallerKitUI
import SnapshotKitTesting
import Testing

@MainActor
struct UpdateHistoryViewSnapshotTests {
    @Test func history() async {
        await assertSnapshots(of: UpdateHistoryView.self)
    }
}
