import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `DeveloperToolsView`; the matrix is declared via
/// `SnapshotProviding` in `DeveloperToolsView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct DeveloperToolsViewSnapshotTests {
    @Test func developerTools() async {
        await assertSnapshots(of: DeveloperToolsView.self)
    }
}
