@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct ScheduleSettingsViewSnapshotTests {
    @Test func screen() async {
        await assertSnapshots(of: ScheduleSettingsView.self)
    }
}
