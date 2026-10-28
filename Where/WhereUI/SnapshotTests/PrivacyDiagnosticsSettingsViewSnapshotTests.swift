import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct PrivacyDiagnosticsSettingsViewSnapshotTests {
    @Test func privacyDiagnostics() async {
        await assertSnapshots(of: PrivacyDiagnosticsSettingsView.self)
    }
}
