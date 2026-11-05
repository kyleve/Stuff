import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct HistoryCompletenessNoticeSnapshotTests {
    @Test func historyCompletenessNotice() async {
        await assertSnapshots(of: HistoryCompletenessNotice.self)
    }
}
