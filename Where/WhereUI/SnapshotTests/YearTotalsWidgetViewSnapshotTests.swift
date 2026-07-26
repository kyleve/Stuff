import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct YearTotalsWidgetViewSnapshotTests {
    @Test func yearTotalsWidget() async {
        await assertSnapshots(of: YearTotalsWidgetView.self)
    }
}
