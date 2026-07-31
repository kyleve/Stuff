import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct MacSummaryWidgetViewSnapshotTests {
    @Test func macSummaryWidget() async {
        await assertSnapshots(of: MacSummaryWidgetView.self)
    }
}
