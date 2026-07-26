import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeveloperOverlaySnapshotTests {
    @Test func developerOverlay() async {
        await assertSnapshots(of: DeveloperOverlay.self)
    }
}
