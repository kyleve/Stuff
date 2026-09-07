import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct EstimatedTimeFeaturesViewSnapshotTests {
    @Test func snapshots() async {
        await assertSnapshots(of: EstimatedTimeFeaturesView.self)
    }
}
