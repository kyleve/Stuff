import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct WidgetCompatibilityViewSnapshotTests {
    @Test func widgetCompatibility() async {
        await assertSnapshots(of: WidgetCompatibilityView.self)
    }
}
