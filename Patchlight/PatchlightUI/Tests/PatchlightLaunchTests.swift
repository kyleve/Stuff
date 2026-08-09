@_spi(Testing) import PatchlightUI
import Testing

@MainActor
struct PatchlightLaunchTests {
    @Test func launchPlanHasOneTypedCompositionStep() {
        #expect(PatchlightLaunch.plan(dependencies: .preview).nodeIDs == [.prepareApplication])
    }

    @Test func applicationLauncherStartsInTheForeground() {
        let launcher = PatchlightLaunch.makeApplicationLauncher(dependencies: .preview)

        #expect(launcher.reason == .userForeground)
        #expect(!launcher.reason.buildsNoViewTree)
    }
}
