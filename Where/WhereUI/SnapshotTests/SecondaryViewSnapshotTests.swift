import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `SecondaryView`; the matrix is declared via
/// `SnapshotProviding` in `SecondaryView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct SecondaryViewSnapshotTests {
    @Test func secondary() async {
        await assertSnapshots(of: SecondaryView.self)
    }
}
