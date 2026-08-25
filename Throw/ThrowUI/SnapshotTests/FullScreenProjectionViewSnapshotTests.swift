import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct FullScreenProjectionViewSnapshotTests {
    @Test func fullScreenProjection() async {
        await assertSnapshots(of: FullScreenProjectionView.self)
    }
}
