import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PresenceTimelineListSnapshotTests {
    @Test func presenceTimeline() async {
        await assertSnapshots(
            of: PresenceTimelineList.self,
            captureMode: { snapshotCase, configuration in
                // The populated timeline’s native toolbar symbol finishes resizing at AX5.
                if snapshotCase.name == "WithData", configuration.dynamicType == .accessibility5 {
                    .standard
                } else {
                    .afterMeasurement
                }
            },
        )
    }
}
