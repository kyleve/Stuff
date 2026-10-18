import InstallerKitUI
import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct AppUpdatesViewSnapshotTests {
    @Test func updates() async {
        await assertSnapshots(of: AppUpdatesView<EmptyModifier>.self)
    }
}
