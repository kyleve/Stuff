import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct RegionsSnippetViewSnapshotTests {
    @Test func regionAppearances() async {
        await assertSnapshots(of: RegionsSnippetView.self)
    }
}
