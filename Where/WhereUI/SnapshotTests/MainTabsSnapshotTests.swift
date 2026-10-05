import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct MainTabsSnapshotTests {
    @Test func mainTabs() async {
        await assertSnapshots(of: MainTabs.self)
    }
}
