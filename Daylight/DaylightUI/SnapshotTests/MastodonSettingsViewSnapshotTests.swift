@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct MastodonSettingsViewSnapshotTests {
    @Test func screen() async {
        await assertSnapshots(of: MastodonSettingsView.self)
    }
}
