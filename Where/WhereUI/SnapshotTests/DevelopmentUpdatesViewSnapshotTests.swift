import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DevelopmentUpdatesViewSnapshotTests {
    @Test func updates() async {
        await assertSnapshots(of: DevelopmentUpdatesView.self)
    }
}
