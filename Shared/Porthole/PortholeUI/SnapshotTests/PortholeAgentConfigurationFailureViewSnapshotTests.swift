@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeAgentConfigurationFailureViewSnapshotTests {
    @Test func setupFailure() async {
        await assertSnapshots(of: PortholeAgentConfigurationFailureView.self)
    }
}
