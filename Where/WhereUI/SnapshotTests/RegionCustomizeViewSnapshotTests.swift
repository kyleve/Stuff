import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionCustomizeViewSnapshotTests {
    @Test func regionCustomize() async {
        await assertSnapshots(of: RegionCustomizeView.self)
    }
}
