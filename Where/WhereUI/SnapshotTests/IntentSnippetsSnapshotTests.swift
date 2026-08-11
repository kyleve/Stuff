import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct IntentSnippetsSnapshotTests {
    @Test func daysInRegionSnippet() async {
        await assertSnapshots(of: DaysInRegionSnippetView.self)
    }

    @Test func regionsSnippet() async {
        await assertSnapshots(of: RegionsSnippetView.self)
    }
}
