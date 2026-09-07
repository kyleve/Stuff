import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ThrowDashboardViewSnapshotTests {
    @Test func dashboardStates() async {
        await assertSnapshots(of: ThrowDashboardView.self)
    }
}
