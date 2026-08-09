@_spi(Testing) import PatchlightUI
import SnapshotKitTesting
import Testing

@MainActor
struct PatchlightDashboardViewSnapshotTests {
    @Test func signedOutDashboard() async {
        await assertSnapshots(of: PatchlightDashboardView.self)
    }
}
