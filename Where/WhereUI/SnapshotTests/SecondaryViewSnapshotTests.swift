import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct SecondaryViewSnapshotTests {
    @Test func secondary() async {
        await assertSnapshots(of: SecondaryView.self)
    }
}
