@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeViewSnapshotTests {
    @Test func capturedIssue() async {
        await assertSnapshots(of: PortholeView.self)
    }
}
