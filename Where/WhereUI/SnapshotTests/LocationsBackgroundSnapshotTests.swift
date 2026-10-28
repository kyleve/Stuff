import SnapshotKitTesting
import Testing
@testable import WhereUI

struct LocationsBackgroundSnapshotTests {
    @Test func locationsBackground() async {
        await assertSnapshots(of: LocationsBackground.self)
    }
}
