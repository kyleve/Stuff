import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct ProjectionIntensitySettingsViewSnapshotTests {
    @Test func projectionIntensitySettings() async {
        await assertSnapshots(of: ProjectionIntensitySettingsView.self)
    }
}
