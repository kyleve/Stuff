@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct SequenceHistoryViewSnapshotTests {
    @Test func screen() async {
        await assertSnapshots(of: SequenceHistoryView.self)
    }
}
