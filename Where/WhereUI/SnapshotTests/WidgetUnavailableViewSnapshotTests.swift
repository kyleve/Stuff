import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct WidgetUnavailableViewSnapshotTests {
    @Test func appearance() async {
        await assertSnapshots(of: WidgetUnavailableView.self)
    }
}
