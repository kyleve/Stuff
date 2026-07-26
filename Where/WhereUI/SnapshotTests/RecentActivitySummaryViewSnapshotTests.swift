import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecentActivitySummaryViewSnapshotTests {
    @Test func recentActivity() async {
        await assertSnapshots(of: RecentActivitySummaryView.self)
    }
}
