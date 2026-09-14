import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeGitHubViewSnapshotTests {
    @Test func workspaceSetup() async {
        await assertSnapshots(of: PortholeGitHubView.self)
    }
}
