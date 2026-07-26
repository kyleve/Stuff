import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct PrimaryViewSnapshotTests {
    @Test func primary() async {
        await assertSnapshots(of: PrimaryView.self)
    }
}
