import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PresenceTimelineListSnapshotTests {
    @Test func presenceTimeline() async {
        await assertSnapshots(of: PresenceTimelineList.self)
    }
}
