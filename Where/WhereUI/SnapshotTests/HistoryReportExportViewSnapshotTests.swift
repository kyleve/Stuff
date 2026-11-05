import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct HistoryReportExportViewSnapshotTests {
    @Test func historyReportExportView() async {
        await assertSnapshots(of: HistoryReportExportView.self)
    }
}
