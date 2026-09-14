@testable import PortholeUI
import SnapshotKitTesting
import Testing

@MainActor
struct PortholeCoverageDeclarationViewSnapshotTests {
    @Test func declaration() async {
        await assertSnapshots(of: PortholeCoverageDeclarationView.self)
    }
}
