import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `RegionDaysView`; the matrix is declared via
/// `SnapshotProviding` in `RegionDaysView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct RegionDaysViewSnapshotTests {
    @Test func regionDays() async {
        await assertSnapshots(of: RegionDaysView.self)
    }
}
