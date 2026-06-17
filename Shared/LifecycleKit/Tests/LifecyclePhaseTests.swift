@testable import LifecycleKit
import Testing

private struct Boom: Error {}

@MainActor
struct LifecyclePhaseTests {
    @Test func launchingAndRunningShareTheSplashSurface() {
        // The anti-flicker invariant: a step advancing keeps showing the splash,
        // so it must not change the surface identity and retrigger a transition.
        let running = LifecyclePhase.running(
            LifecycleStep.work("a") { _ in },
            LifecycleStepUIBridge(reason: .userForeground),
        )
        #expect(LifecyclePhase.launching.surfaceIdentity == .splash)
        #expect(running.surfaceIdentity == .splash)
    }

    @Test func runningStepsAllCollapseToTheSameSurface() {
        // Advancing from one running step to the next is still the splash surface.
        let first = LifecyclePhase.running(
            LifecycleStep.work("first") { _ in },
            LifecycleStepUIBridge(reason: .userForeground),
        )
        let second = LifecyclePhase.running(
            LifecycleStep.work("second") { _ in },
            LifecycleStepUIBridge(reason: .userForeground),
        )
        #expect(first.surfaceIdentity == second.surfaceIdentity)
    }

    @Test func readyIsItsOwnSurface() {
        #expect(LifecyclePhase.ready.surfaceIdentity == .ready)
        #expect(LifecyclePhase.ready.surfaceIdentity != .splash)
    }

    @Test func failuresAreIdentifiedByTheFailingStep() {
        // Re-failing at a *different* step is a real surface change (animates);
        // failing at the same step twice is not.
        let boom = LifecyclePhase.failed(LifecycleFailure(stepID: "boom", error: Boom()))
        let bang = LifecyclePhase.failed(LifecycleFailure(stepID: "bang", error: Boom()))
        let boomAgain = LifecyclePhase.failed(LifecycleFailure(stepID: "boom", error: Boom()))
        #expect(boom.surfaceIdentity == .failed("boom"))
        #expect(boom.surfaceIdentity == boomAgain.surfaceIdentity)
        #expect(boom.surfaceIdentity != bang.surfaceIdentity)
    }
}
