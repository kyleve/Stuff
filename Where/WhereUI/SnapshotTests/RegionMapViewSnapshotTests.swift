import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionMapViewSnapshotTests {
    @Test func regionMap() async {
        await assertSnapshots(of: RegionMapView.self)
    }
}
