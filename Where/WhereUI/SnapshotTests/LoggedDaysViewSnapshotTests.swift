import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct LoggedDaysViewSnapshotTests {
    @Test func loggedDays() async {
        await assertSnapshots(of: LoggedDaysView.self)
    }
}
