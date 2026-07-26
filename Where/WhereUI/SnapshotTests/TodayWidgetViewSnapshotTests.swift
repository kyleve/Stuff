import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct TodayWidgetViewSnapshotTests {
    @Test func todayWidget() async {
        await assertSnapshots(of: TodayWidgetView.self)
    }
}
