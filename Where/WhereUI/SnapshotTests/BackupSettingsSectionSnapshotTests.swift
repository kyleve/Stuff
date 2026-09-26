import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct BackupSettingsSectionSnapshotTests {
    @Test func backupSettings() async {
        await assertSnapshots(of: BackupSettingsSection.self)
    }
}
