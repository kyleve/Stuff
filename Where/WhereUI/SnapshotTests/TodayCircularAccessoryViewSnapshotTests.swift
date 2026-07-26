import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct TodayCircularAccessoryViewSnapshotTests {
    @Test func todayCircularAccessory() async {
        await assertSnapshots(of: TodayCircularAccessoryView.self)
    }
}
