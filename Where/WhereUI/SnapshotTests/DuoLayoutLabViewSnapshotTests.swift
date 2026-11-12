import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DuoLayoutLabViewSnapshotTests {
    @Test func duoLayoutLab() async {
        await assertSnapshots(of: DuoLayoutLabView.self)
    }
}
