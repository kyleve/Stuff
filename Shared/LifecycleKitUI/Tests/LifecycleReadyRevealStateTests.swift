@testable import LifecycleKitUI
import Testing

struct LifecycleReadyRevealStateTests {
    private let minimumSplashDuration = Duration.milliseconds(800)

    @Test func zeroMinimumStartsRevealed() {
        let state = LifecycleReadyRevealState(minimumSplashDuration: .zero)

        #expect(state.canRevealReady)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func positiveMinimumStartsAwaitingTheFirstVisibleReady() {
        let state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(state.canRevealReady == false)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func firstVisibleReadyStartsAHoldWhenNoSplashRendered() {
        let readyInstant = ContinuousClock.now
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )

        state.readyBecameVisible(
            at: readyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(
            state.splashHoldDeadline
                == readyInstant.advanced(by: minimumSplashDuration),
        )
        #expect(state.canRevealReady == false)
    }

    @Test func visibleReadyKeepsTheRenderedSplashDeadline() {
        let splashInstant = ContinuousClock.now
        let readyInstant = splashInstant.advanced(by: .milliseconds(400))
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state.splashAppeared(
            at: splashInstant,
            minimumSplashDuration: minimumSplashDuration,
        )
        let originalDeadline = state.splashHoldDeadline

        state.readyBecameVisible(
            at: readyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(state.splashHoldDeadline == originalDeadline)
    }

    @Test func visibleReadyDoesNotReplayAfterContentWasRevealed() {
        let readyInstant = ContinuousClock.now
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state = .revealed

        state.readyBecameVisible(
            at: readyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(state.canRevealReady)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func interruptedHoldOwesANewFirstVisibleReveal() {
        let firstReadyInstant = ContinuousClock.now
        let resumedReadyInstant = firstReadyInstant.advanced(by: .seconds(5))
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state.readyBecameVisible(
            at: firstReadyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        state.sceneBecameInactive()
        state.readyBecameVisible(
            at: resumedReadyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(
            state.splashHoldDeadline
                == resumedReadyInstant.advanced(by: minimumSplashDuration),
        )
        #expect(state.canRevealReady == false)
    }

    @Test func sceneInactivityDoesNotReplayAfterContentWasRevealed() {
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state = .revealed

        state.sceneBecameInactive()

        #expect(state.canRevealReady)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func sceneInactivityBeforeTheUncoveredFrameStillOwesAReveal() {
        let readyInstant = ContinuousClock.now
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state.readyBecameVisible(
            at: readyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )
        state.splashHoldElapsed()
        #expect(state.canRevealReady)

        state.sceneBecameInactive()

        #expect(state.canRevealReady == false)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func committedUncoveredFrameMakesTheRevealSticky() {
        let readyInstant = ContinuousClock.now
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state.readyBecameVisible(
            at: readyInstant,
            minimumSplashDuration: minimumSplashDuration,
        )
        state.splashHoldElapsed()

        state.contentDidReveal()
        state.sceneBecameInactive()

        #expect(state.canRevealReady)
        #expect(state.splashHoldDeadline == nil)
    }

    @Test func aLaterRenderedSplashRearmsTheMinimum() {
        let splashInstant = ContinuousClock.now
        var state = LifecycleReadyRevealState(
            minimumSplashDuration: minimumSplashDuration,
        )
        state = .revealed
        #expect(state.canRevealReady)

        state.splashAppeared(
            at: splashInstant,
            minimumSplashDuration: minimumSplashDuration,
        )

        #expect(
            state.splashHoldDeadline
                == splashInstant.advanced(by: minimumSplashDuration),
        )
        #expect(state.canRevealReady == false)
    }
}
