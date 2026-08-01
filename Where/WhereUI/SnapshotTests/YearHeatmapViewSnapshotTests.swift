import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearHeatmapViewSnapshotTests {
    @Test func yearHeatmap() async {
        await assertSnapshots(of: YearHeatmapView.self)
    }
}
