@_spi(Testing) import PatchlightUI
import Testing

@MainActor
struct PatchlightLaunchTests {
    @Test func launchPlanHasOneTypedCompositionStep() {
        #expect(PatchlightLaunch.plan(dependencies: .preview).nodeIDs == [.prepareApplication])
    }
}
