import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LoggedDaysViewSnapshotTests {
    @Test func loggedDays() async {
        await assertSnapshots(of: LoggedDaysView.self)
    }
}
