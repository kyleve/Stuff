import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `DeveloperOverlay`; the matrix is declared via
/// `SnapshotProviding` in `DeveloperOverlay.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct DeveloperOverlaySnapshotTests {
    @Test func developerOverlay() async {
        await assertSnapshots(of: DeveloperOverlay.self)
    }
}
