import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DataSettingsViewSnapshotTests {
    @Test func data() async {
        await assertSnapshots(of: DataSettingsView.self)
    }
}
