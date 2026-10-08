import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PlanningRegionPickerViewSnapshotTests {
    @Test func planningRegionPicker() async {
        await assertSnapshots(of: PlanningRegionPickerView.self)
    }
}
