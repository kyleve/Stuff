import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AbruptChangeDetailViewSnapshotTests {
    @Test func abruptChangeDetail() async {
        await assertSnapshots(of: AbruptChangeDetailView.self)
    }
}
