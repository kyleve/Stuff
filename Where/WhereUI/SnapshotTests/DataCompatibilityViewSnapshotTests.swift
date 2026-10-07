import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DataCompatibilityViewSnapshotTests {
    @Test func appearance() async {
        await assertSnapshots(of: DataCompatibilityView.self)
    }
}
