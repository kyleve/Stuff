import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct MainViewSnapshotTests {
    @Test func mainView() async {
        await assertSnapshots(of: MainView.self)
    }
}
