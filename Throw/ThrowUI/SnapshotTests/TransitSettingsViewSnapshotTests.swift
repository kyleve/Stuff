import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct TransitSettingsViewSnapshotTests {
    @Test func transitSettings() async {
        await assertSnapshots(of: TransitSettingsView.self)
    }
}
