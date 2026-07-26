import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PresenceTimelineViewSnapshotTests {
    @Test func presenceTimeline() async {
        await assertSnapshots(of: PresenceTimelineView.self)
    }
}
