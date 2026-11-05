import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AlertsSettingsViewSnapshotTests {
    @Test func alertsSettings() async {
        await assertSnapshots(of: AlertsSettingsView.self)
    }
}
