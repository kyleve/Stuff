import SnapshotKit
import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct MainTabsSnapshotTests {
    @Test func mainTabs() async {
        await assertSnapshots(of: SharedWorldSnapshots.self)
    }

    private enum SharedWorldSnapshots: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            MainTabs.snapshots(buildWorld: SnapshotWorldFixture.shared.load)
        }
    }
}
