import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `SettingsView`; the matrix is declared via
/// `SnapshotProviding` in `SettingsView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct SettingsViewSnapshotTests {
    @Test func settings() async {
        await assertSnapshots(of: SettingsView.self)
    }
}
