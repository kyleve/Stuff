@testable import LifecycleKitUI
import Testing

struct LifecycleReadyRevealPolicyTests {
    @Test func phaseDrivenStartsRevealedWithoutAnObservedSplash() {
        let state = LifecycleReadyRevealState(
            policy: .phaseDriven,
            minimumSplashDuration: .seconds(60),
        )

        #expect(state.canRevealReady)
    }

    @Test func splashBeforeFirstRevealWithZeroMinimumStartsRevealed() {
        let state = LifecycleReadyRevealState(
            policy: .splashBeforeFirstReveal,
            minimumSplashDuration: .zero,
        )

        #expect(state.canRevealReady)
    }

    @Test func splashBeforeFirstRevealWithPositiveMinimumAwaitsPresentation() {
        let state = LifecycleReadyRevealState(
            policy: .splashBeforeFirstReveal,
            minimumSplashDuration: .milliseconds(800),
        )

        #expect(state.canRevealReady == false)
        #expect(state.splashHoldDeadline == nil)
    }
}
