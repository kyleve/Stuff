@testable import InstallerKitUI
import SnapshotKitTesting
import Testing

@MainActor
struct UpdateBrowserViewSnapshotTests {
    @Test func browser() async {
        await assertSnapshots(of: UpdateBrowserView.self)
    }
}
