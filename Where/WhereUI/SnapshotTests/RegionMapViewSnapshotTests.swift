import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `RegionMapView` (the deterministic capture stand-in);
/// the matrix is declared via `SnapshotProviding` in `RegionMapView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct RegionMapViewSnapshotTests {
    @Test func regionMap() async {
        await assertSnapshots(of: RegionMapView.self)
    }
}
