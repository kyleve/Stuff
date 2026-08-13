import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct WhereLifecycleFailureViewSnapshotTests {
    @Test func lifecycleFailure() async {
        await assertSnapshots(of: WhereLifecycleFailureView.self)
    }
}
