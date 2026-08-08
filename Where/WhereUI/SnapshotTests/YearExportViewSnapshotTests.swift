import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct YearExportViewSnapshotTests {
    @Test func yearExport() async {
        await assertSnapshots(of: YearExportView.self)
    }
}
