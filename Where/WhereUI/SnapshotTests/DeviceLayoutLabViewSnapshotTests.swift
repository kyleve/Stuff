import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeviceLayoutLabViewSnapshotTests {
    @Test func deviceLayoutLab() async {
        await assertSnapshots(of: DeviceLayoutLabView.self)
    }
}
