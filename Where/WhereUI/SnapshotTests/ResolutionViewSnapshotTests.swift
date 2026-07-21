import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `ResolutionView`; the matrix is declared via
/// `SnapshotProviding` in `ResolutionView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct ResolutionViewSnapshotTests {
    @Test func resolution() async {
        await assertSnapshots(of: ResolutionView.self)
    }
}
