@testable import InstallerKitUI
import SnapshotKitTesting
import Testing

@MainActor
struct UpdateFailureCardSnapshotTests {
    @Test func failure() async {
        await assertSnapshots(of: UpdateFailureCard.self)
    }
}
