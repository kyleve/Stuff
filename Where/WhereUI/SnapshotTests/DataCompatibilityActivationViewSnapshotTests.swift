import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DataCompatibilityActivationViewSnapshotTests {
    @Test func appearance() async {
        await assertSnapshots(of: DataCompatibilityActivationView.self)
    }
}
