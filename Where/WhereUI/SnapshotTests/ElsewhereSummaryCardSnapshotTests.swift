import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct ElsewhereSummaryCardSnapshotTests {
    @Test func elsewhereSummaryCard() async {
        await assertSnapshots(of: ElsewhereSummaryCard.self)
    }
}
