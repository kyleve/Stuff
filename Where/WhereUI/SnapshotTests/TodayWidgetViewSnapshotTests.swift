import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct TodayWidgetViewSnapshotTests {
    @Test func todayWidget() async {
        await assertSnapshots(of: TodayWidgetView.self)
    }
}
