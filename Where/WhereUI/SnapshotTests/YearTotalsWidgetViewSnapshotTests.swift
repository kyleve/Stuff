import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearTotalsWidgetViewSnapshotTests {
    @Test func yearTotalsWidget() async {
        await assertSnapshots(of: YearTotalsWidgetView.self)
    }
}
