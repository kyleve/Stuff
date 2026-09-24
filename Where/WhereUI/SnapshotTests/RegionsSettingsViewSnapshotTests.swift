import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionsSettingsViewSnapshotTests {
    @Test func regionsSettings() async {
        await assertSnapshots(of: RegionsSettingsView.self)
    }
}
