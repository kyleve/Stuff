import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionSummaryCardSnapshotTests {
    @Test func componentThemes() async {
        await assertSnapshots(of: RegionSummaryCard.self)
    }
}
