import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct RegionMapViewSnapshotTests {
    @Test func regionMap() async {
        await assertSnapshots(of: RegionMapView.self)
    }
}
