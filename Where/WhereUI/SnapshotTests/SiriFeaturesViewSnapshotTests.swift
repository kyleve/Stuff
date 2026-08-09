import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct SiriFeaturesViewSnapshotTests {
    @Test func siriFeatures() async {
        await assertSnapshots(of: SiriFeaturesView.self)
    }
}
