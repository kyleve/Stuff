import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct RootViewSnapshotTests {
    @Test func root() async {
        await assertSnapshots(of: RootView.self)
    }
}
