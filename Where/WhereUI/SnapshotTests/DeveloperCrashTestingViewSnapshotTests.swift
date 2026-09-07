import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct DeveloperCrashTestingViewSnapshotTests {
    @Test func developerCrashTestingView() async {
        await assertSnapshots(of: DeveloperCrashTestingView.self)
    }
}
