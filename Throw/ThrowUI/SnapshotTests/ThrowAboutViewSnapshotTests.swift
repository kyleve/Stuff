import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ThrowAboutViewSnapshotTests {
    @Test func about() async {
        await assertSnapshots(of: ThrowAboutView.self)
    }
}
