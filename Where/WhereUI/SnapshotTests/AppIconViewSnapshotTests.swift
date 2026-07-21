import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `AppIconView`; the matrix is declared via
/// `SnapshotProviding` in `AppIconView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct AppIconViewSnapshotTests {
    @Test func appIcon() async {
        await assertSnapshots(of: AppIconView.self)
    }
}
