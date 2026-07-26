import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct LaunchSplashViewSnapshotTests {
    @Test func launchSplash() async {
        await assertSnapshots(of: LaunchSplashView.self)
    }
}
