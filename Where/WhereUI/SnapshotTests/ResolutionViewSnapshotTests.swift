import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct ResolutionViewSnapshotTests {
    @Test func resolution() async {
        await assertSnapshots(of: ResolutionView.self)
    }
}
