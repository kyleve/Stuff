import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LocationForecastPanelSnapshotTests {
    @Test func componentThemes() async {
        await assertSnapshots(of: LocationForecastPanel.self)
    }
}
