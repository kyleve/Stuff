import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DevicesSettingsViewSnapshotTests {
    @Test func devices() async {
        await assertSnapshots(of: DevicesSettingsView.self)
    }
}
