import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PresenceTimelineListSnapshotTests {
    @Test func presenceTimelineLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<PresenceTimelineList>.self,
            testName: "presenceTimeline()",
        )
    }

    @Test func presenceTimelineExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<PresenceTimelineList>.self,
            testName: "presenceTimeline()",
        )
    }
}

extension PresenceTimelineList: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["WithData"]
    }
}
