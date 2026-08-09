import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct OnboardingPhotoImportViewSnapshotTests {
    @Test func photoImport() async {
        await assertSnapshots(of: OnboardingPhotoImportView.self)
    }
}
