import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrivacyBackupsFeaturesViewSnapshotTests {
    @Test func gallery() async {
        await assertSnapshots(of: PrivacyBackupsFeaturesView.self)
    }
}
