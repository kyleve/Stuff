import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DataCompatibilityViewSnapshotTests {
    @Test func dataCompatibility() async {
        await assertSnapshots(of: DataCompatibilityView.self)
    }
}
