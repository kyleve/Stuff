import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationsViewSnapshotTests {
    @Test func locations() async {
        await assertSnapshots(of: LocationsView.self)
    }
}
