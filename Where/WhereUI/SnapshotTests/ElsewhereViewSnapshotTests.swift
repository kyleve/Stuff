import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct ElsewhereViewSnapshotTests {
    @Test func elsewhere() async {
        await assertSnapshots(of: ElsewhereView.self)
    }
}
