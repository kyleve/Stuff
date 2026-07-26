import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct AppIconViewSnapshotTests {
    @Test func appIcon() async {
        await assertSnapshots(of: AppIconView.self)
    }
}
