import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearViewSnapshotTests {
    @Test func year() async {
        await assertSnapshots(of: YearView.self)
    }
}
