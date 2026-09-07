import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct AppearanceSettingsViewSnapshotTests {
    @Test func appearanceSettings() async {
        await assertSnapshots(of: AppearanceSettingsView.self)
    }
}
