import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct SettingsViewSnapshotTests {
    @Test func settings() async {
        await assertSnapshots(of: SettingsView.self)
    }
}
