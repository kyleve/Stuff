import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AboutSettingsViewSnapshotTests {
    @Test func about() async {
        await assertSnapshots(of: AboutSettingsView.self)
    }
}
