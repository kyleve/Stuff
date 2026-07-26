import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
@Suite(.snapshots(record: .missing))
struct PresenceTimelineViewSnapshotTests {
    @Test func presenceTimeline() async {
        await assertSnapshots(of: PresenceTimelineView.self)
    }
}
