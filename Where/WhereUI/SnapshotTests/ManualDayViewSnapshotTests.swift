import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct ManualDayViewSnapshotTests {
    @Test func manualDay() async {
        await assertSnapshots(of: ManualDayView.self)
    }
}
