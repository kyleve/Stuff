import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `LaunchSplashView`; the matrix is declared via
/// `SnapshotProviding` in `LaunchSplashView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct LaunchSplashViewSnapshotTests {
    @Test func launchSplash() async {
        await assertSnapshots(of: LaunchSplashView.self)
    }
}
