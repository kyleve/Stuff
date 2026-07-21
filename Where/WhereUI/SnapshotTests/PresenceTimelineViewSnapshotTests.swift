import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `PresenceTimelineView`; the matrix is declared via
/// `SnapshotProviding` in `PresenceTimelineView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct PresenceTimelineViewSnapshotTests {
    @Test func presenceTimeline() async {
        await assertSnapshots(of: PresenceTimelineView.self)
    }
}
