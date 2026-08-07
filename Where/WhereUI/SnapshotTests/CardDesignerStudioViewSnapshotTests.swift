import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct CardDesignerStudioViewSnapshotTests {
    @Test func cardDesignerStudio() async {
        await assertSnapshots(of: CardDesignerStudioView.self)
    }
}
