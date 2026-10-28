import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct InsightsAccuracyFeaturesViewSnapshotTests {
    @Test func insightsAccuracyFeatures() async {
        await assertSnapshots(of: InsightsAccuracyFeaturesView.self)
    }
}
