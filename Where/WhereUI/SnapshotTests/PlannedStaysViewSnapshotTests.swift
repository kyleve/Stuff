import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PlannedStaysViewSnapshotTests {
    @Test func plannedStays() async {
        await assertSnapshots(of: PlannedStaysView.self)
    }
}
