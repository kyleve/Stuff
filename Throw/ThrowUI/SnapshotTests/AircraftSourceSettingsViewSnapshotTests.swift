import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct AircraftSourceSettingsViewSnapshotTests {
    @Test func aircraftSourceSettings() async {
        await assertSnapshots(of: AircraftSourceSettingsView.self)
    }
}
