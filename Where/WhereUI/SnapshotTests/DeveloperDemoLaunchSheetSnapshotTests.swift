import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeveloperDemoLaunchSheetSnapshotTests {
    @Test func developerDemoLaunchSheet() async {
        await assertSnapshots(of: DeveloperDemoLaunchSheet.self)
    }
}
