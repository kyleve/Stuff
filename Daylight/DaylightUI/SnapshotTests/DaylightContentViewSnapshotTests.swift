@testable import DaylightUI
import SnapshotKitTesting
import Testing

@MainActor
struct DaylightContentViewSnapshotTests {
    @Test func screens() async {
        await assertSnapshots(of: DaylightContentView.self)
    }
}
