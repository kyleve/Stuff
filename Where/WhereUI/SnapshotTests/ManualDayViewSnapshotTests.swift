import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct ManualDayViewSnapshotTests {
    @Test func manualDay() async {
        await assertSnapshots(of: ManualDayView.self)
    }
}
