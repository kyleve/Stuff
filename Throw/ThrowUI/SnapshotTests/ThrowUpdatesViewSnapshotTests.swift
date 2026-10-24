import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ThrowUpdatesViewSnapshotTests {
    @Test func updates() async {
        await assertSnapshots(of: ThrowUpdatesView.self)
    }
}
