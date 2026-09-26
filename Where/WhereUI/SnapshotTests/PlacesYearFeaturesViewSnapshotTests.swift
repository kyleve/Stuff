import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PlacesYearFeaturesViewSnapshotTests {
    @Test func gallery() async {
        await assertSnapshots(of: PlacesYearFeaturesView.self)
    }
}
