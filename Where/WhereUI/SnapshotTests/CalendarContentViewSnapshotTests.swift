import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct CalendarContentViewSnapshotTests {
    @Test func calendarContent() async {
        await assertSnapshots(of: CalendarContentView.self)
    }
}
