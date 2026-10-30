import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func seasonalDocuments() async {
        await assertSnapshots(of: LocationsView.SeasonalThemes.self)
    }

    @Test func locations() async {
        await assertSnapshots(of: LocationsView.self)
    }
}
