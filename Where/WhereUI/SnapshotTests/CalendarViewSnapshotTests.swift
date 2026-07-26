import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct CalendarViewSnapshotTests {
    @Test func calendar() async {
        await assertSnapshots(of: CalendarView.self)
    }
}
