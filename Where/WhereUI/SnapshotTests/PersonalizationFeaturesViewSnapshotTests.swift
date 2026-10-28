import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PersonalizationFeaturesViewSnapshotTests {
    @Test func personalizationFeatures() async {
        await assertSnapshots(of: PersonalizationFeaturesView.self)
    }
}
