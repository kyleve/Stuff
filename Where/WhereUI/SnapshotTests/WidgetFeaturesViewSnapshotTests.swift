import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct WidgetFeaturesViewSnapshotTests {
    @Test func widgetFeatures() async {
        await assertSnapshots(of: WidgetFeaturesView.self)
    }
}
