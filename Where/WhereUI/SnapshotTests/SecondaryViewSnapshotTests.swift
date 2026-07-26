import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct SecondaryViewSnapshotTests {
    @Test func secondary() async {
        await assertSnapshots(of: SecondaryView.self)
    }
}
