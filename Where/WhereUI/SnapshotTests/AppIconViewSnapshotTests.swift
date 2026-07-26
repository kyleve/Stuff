import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct AppIconViewSnapshotTests {
    @Test func appIcon() async {
        await assertSnapshots(of: AppIconView.self)
    }
}
