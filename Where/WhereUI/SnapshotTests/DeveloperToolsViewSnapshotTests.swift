import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeveloperToolsViewSnapshotTests {
    @Test func developerTools() async {
        await assertSnapshots(of: DeveloperToolsView.self)
    }
}
