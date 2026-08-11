import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct BackupPreparationViewSnapshotTests {
    @Test func backupPreparation() async {
        await assertSnapshots(of: BackupPreparationView.self)
    }
}
