import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct CalendarViewSnapshotTests {
    @Test func calendar() async {
        await assertSnapshots(of: CalendarView.self)
    }
}
