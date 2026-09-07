import SnapshotKitTesting
import Testing
@testable import ThrowUI

@MainActor
struct SettingsFailureMessagesSnapshotTests {
    @Test func ownerFailures() async {
        await assertSnapshots(of: SettingsFailureMessages.self)
    }
}
