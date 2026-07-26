import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct SettingsViewSnapshotTests {
    @Test func settings() async {
        await assertSnapshots(of: SettingsView.self)
    }
}
