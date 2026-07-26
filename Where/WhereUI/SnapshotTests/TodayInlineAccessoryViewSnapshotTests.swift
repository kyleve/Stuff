import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct TodayInlineAccessoryViewSnapshotTests {
    @Test func todayInlineAccessory() async {
        await assertSnapshots(of: TodayInlineAccessoryView.self)
    }
}
