import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RecordingDeviceRoleViewSnapshotTests {
    @Test func roles() async {
        await assertSnapshots(of: RecordingDeviceRoleView.self)
    }
}
