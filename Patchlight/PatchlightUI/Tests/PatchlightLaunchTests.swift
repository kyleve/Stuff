import PatchlightUI
import Testing

@MainActor
struct PatchlightLaunchTests {
    @Test func launchPlanHasOneTypedCompositionStep() {
        #expect(PatchlightLaunch.plan().nodeIDs == [.prepareApplication])
    }
}
