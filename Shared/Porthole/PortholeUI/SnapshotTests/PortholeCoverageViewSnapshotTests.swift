@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeCoverageViewSnapshotTests {
    @Test func coverage() async {
        await assertSnapshots(of: PortholeCoverageView.self)
    }
}
