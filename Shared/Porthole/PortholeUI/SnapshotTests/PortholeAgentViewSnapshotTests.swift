@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeAgentViewSnapshotTests {
    @Test func setupAndConversation() async {
        await assertSnapshots(of: PortholeAgentView.self)
    }
}
