import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AppearanceSettingsViewSnapshotTests {
    @Test func appearance() async {
        await assertSnapshots(of: AppearanceSettingsView.self)
    }
}
