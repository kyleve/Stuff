import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrimaryViewSnapshotTests {
    @Test func primary() async {
        await assertSnapshots(of: PrimaryView.self)
    }
}
