import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct TodayCircularAccessoryViewSnapshotTests {
    @Test func todayCircularAccessory() async {
        await assertSnapshots(of: TodayCircularAccessoryView.self)
    }
}
