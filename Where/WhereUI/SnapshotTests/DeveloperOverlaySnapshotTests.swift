import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct DeveloperOverlaySnapshotTests {
    @Test func developerOverlay() async {
        await assertSnapshots(of: DeveloperOverlay.self)
    }
}
