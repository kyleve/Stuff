import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `PrimaryView`. The matrix is declared once via
/// `SnapshotProviding` in `PrimaryView.swift` (which also drives its `#Preview`
/// cutsheet), so the test is a single `assertSnapshots(of:)` call.
@MainActor
@Suite(.snapshots(record: .missing))
struct PrimaryViewSnapshotTests {
    @Test func primary() async {
        await assertSnapshots(of: PrimaryView.self)
    }
}
