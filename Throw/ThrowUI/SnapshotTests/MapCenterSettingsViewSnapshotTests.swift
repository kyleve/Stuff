import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct MapCenterSettingsViewSnapshotTests {
    @Test func snapshots() async {
        await assertSnapshots(of: MapCenterSettingsView.self)
    }
}
