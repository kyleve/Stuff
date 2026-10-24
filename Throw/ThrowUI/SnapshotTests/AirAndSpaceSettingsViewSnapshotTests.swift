import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct AirAndSpaceSettingsViewSnapshotTests {
    @Test func airAndSpaceSettings() async {
        await assertSnapshots(of: AirAndSpaceSettingsView.self)
    }
}
