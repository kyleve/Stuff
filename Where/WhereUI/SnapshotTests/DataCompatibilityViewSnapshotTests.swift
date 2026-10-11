import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DataCompatibilityViewSnapshotTests {
    @Test func compatibility() async {
        await assertSnapshots(of: DataCompatibilityView.self)
    }
}
