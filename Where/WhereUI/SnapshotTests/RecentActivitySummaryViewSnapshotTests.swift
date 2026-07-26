import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct RecentActivitySummaryViewSnapshotTests {
    @Test func recentActivity() async {
        await assertSnapshots(of: RecentActivitySummaryView.self)
    }
}
