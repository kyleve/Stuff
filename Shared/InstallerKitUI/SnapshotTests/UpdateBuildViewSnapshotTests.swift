@testable import InstallerKitUI
import SnapshotKitTesting
import Testing

@MainActor
struct UpdateBuildViewSnapshotTests {
    @Test func build() async {
        await assertSnapshots(of: UpdateBuildView.self)
    }
}
