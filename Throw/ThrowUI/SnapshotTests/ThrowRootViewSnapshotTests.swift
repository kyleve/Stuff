import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ThrowRootViewSnapshotTests {
    @Test func root() async {
        await assertSnapshots(of: ThrowRootView.self)
    }
}
