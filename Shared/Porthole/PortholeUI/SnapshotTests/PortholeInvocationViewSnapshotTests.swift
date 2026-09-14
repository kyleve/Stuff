@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeInvocationViewSnapshotTests {
    @Test func invocation() async {
        await assertSnapshots(of: PortholeInvocationView.self)
    }
}
