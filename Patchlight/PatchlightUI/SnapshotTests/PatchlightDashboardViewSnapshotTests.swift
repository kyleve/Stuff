@_spi(Testing) import PatchlightUI
import SnapshotKitTesting
import Testing

@MainActor
struct PatchlightDashboardViewSnapshotTests {
    @Test func signedOutDashboard() async {
        await assertSnapshots(of: PatchlightDashboardView.self)
    }

    @Test func onboarding() async {
        await assertSnapshots(of: PatchlightOnboardingSnapshots.self)
    }

    @Test func pullRequestWorkspace() async {
        await assertSnapshots(of: PatchlightWorkspaceSnapshots.self)
    }

    @Test func snapshotWorkspace() async {
        await assertSnapshots(of: PatchlightSnapshotWorkspaceSnapshots.self)
    }
}
