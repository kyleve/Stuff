import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AdaptiveHistoryLabViewSnapshotTests {
    @Test func adaptiveHistoryLab() async {
        await assertSnapshots(of: AdaptiveHistoryLabView.self)
    }
}
