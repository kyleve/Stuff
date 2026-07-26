import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct TodayInlineAccessoryViewSnapshotTests {
    @Test func todayInlineAccessory() async {
        await assertSnapshots(of: TodayInlineAccessoryView.self)
    }
}
