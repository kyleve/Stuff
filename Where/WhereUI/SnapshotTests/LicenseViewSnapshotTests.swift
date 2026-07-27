import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct LicenseViewSnapshotTests {
    @Test func license() async {
        await assertSnapshots(of: LicenseView.self)
    }
}
