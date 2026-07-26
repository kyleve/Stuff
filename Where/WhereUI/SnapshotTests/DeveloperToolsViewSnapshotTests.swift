import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct DeveloperToolsViewSnapshotTests {
    @Test func developerTools() async {
        await assertSnapshots(of: DeveloperToolsView.self)
    }
}
