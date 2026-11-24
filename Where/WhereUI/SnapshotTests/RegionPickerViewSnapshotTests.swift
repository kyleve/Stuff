import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionPickerViewSnapshotTests {
    @Test func picker() async {
        await assertSnapshots(of: RegionPickerView.self, captureMode: .afterMeasurement)
    }
}
