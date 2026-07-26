import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct DayRelabelViewSnapshotTests {
    @Test func dayRelabel() async {
        await assertSnapshots(of: DayRelabelView.self)
    }
}
