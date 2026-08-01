import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearBreakdownViewSnapshotTests {
    @Test func yearBreakdown() async {
        await assertSnapshots(of: YearBreakdownView.self)
    }
}
