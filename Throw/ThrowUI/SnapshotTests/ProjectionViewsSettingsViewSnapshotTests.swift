import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ProjectionViewsSettingsViewSnapshotTests {
    @Test func viewsSettings() async {
        await assertSnapshots(of: ProjectionViewsSettingsView.self)
    }
}
