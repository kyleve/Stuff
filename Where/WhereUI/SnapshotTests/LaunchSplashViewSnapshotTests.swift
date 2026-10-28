import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LaunchSplashViewSnapshotTests {
    @Test func launchSplash() async {
        await assertSnapshots(of: LaunchSplashView.self)
    }
}
