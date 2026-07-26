import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct RegionDaysViewSnapshotTests {
    @Test func regionDays() async {
        await assertSnapshots(of: RegionDaysView.self)
    }
}
