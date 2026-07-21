import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for the logged-in `RootView`; the matrix is declared via
/// `SnapshotProviding` in `RootView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct RootViewSnapshotTests {
    @Test func root() async {
        await assertSnapshots(of: RootView.self)
    }
}
