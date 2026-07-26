import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RootViewSnapshotTests {
    @Test func root() async {
        await assertSnapshots(of: RootView.self)
    }
}
