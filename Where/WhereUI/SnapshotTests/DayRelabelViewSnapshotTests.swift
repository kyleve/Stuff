import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DayRelabelViewSnapshotTests {
    @Test func dayRelabel() async {
        await assertSnapshots(of: DayRelabelView.self)
    }
}
