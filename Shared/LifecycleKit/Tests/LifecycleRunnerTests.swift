@testable import LifecycleKit
import SwiftUI
import Testing

private struct StepError: Error {}

/// Polls `condition` on the main actor until it holds or the timeout elapses.
/// Sleeping yields to the runner's drive task between checks.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline {
            throw StepError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
struct LifecycleRunnerDriveTests {
    @Test func runsStepsInDeclarationOrder() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep.work("b") { _ in executed.append("b") }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        await runner.run()
        #expect(executed == ["a", "b", "c"])
        #expect(runner.phase.isReady)
    }

    @Test func skipsStepsWhoseConditionIsFalse() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep.work("skip", condition: { false }) { _ in executed.append("skip") }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        await runner.run()
        #expect(executed == ["a", "c"])
    }

    @Test func filtersStepsByLaunchReason() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep.work("always") { _ in executed.append("always") }
            LifecycleStep.work("fg", modes: .foreground) { _ in executed.append("fg") }
            LifecycleStep.work("bg", modes: .background) { _ in executed.append("bg") }
        })
        await runner.run()
        #expect(executed == ["always", "bg"])
    }

    @Test func interactiveStepsAreSkippedInBackground() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep
                .interactive("onboarding", perform: { _ in executed.append("onboarding") }) { _ in
                    Text("onboarding")
                }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        await runner.run()
        #expect(executed == ["a", "c"])
        #expect(runner.phase.isReady)
    }

    @Test func runIsIdempotent() async {
        var count = 0
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in count += 1 }
        })
        await runner.run()
        await runner.run()
        #expect(count == 1)
    }
}

@MainActor
struct LifecycleRunnerForegroundPromotionTests {
    @Test func enterForegroundReDrivesAndRunsForegroundOnlySteps() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep.work("store") { _ in executed.append("store") }
            LifecycleStep
                .work("onboarding", modes: .foreground) { _ in executed.append("onboarding") }
        })
        await runner.run()
        // The headless background drive ran only the unrestricted step.
        #expect(executed == ["store"])
        #expect(runner.reason.isBackground)

        await runner.enterForeground()
        // Promotion re-drives from the top: the (idempotent) unrestricted step
        // runs again and the foreground-only step now runs too.
        #expect(executed == ["store", "store", "onboarding"])
        #expect(!runner.reason.isBackground)
        #expect(runner.phase.isReady)
    }

    @Test func enterForegroundIsNoOpForAForegroundLaunch() async {
        var count = 0
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in count += 1 }
        })
        await runner.run()
        await runner.enterForeground()
        #expect(count == 1)
        #expect(runner.phase.isReady)
    }

    @Test func enterForegroundCancelsAndDrainsAnInFlightBackgroundDrive() async throws {
        var starts = 0
        var inFlight = 0
        var maxInFlight = 0
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep.work("slow") { bridge in
                starts += 1
                inFlight += 1
                defer { inFlight -= 1 }
                maxInFlight = max(maxInFlight, inFlight)
                try await bridge.waitForResolution()
            }
        })
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("slow") }

        // Promote while the background drive is parked in "slow". Promotion
        // cancels that drive (its `waitForResolution()` throws), drains it, and
        // only then re-drives "slow" for the foreground launch — never two at
        // once.
        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { starts == 2 }

        runner.phase.runningBridge?.complete()
        await runTask.value
        await promote.value

        #expect(maxInFlight == 1)
        #expect(!runner.reason.isBackground)
        #expect(runner.phase.isReady)
    }
}

@MainActor
struct LifecycleRunnerCancellationTests {
    @Test func resetCancelsAParkedInteractiveStepInsteadOfHanging() async throws {
        // Without cooperative cancellation, `teardown()` would await the run
        // drive forever: it is parked on an interactive step waiting for a tap
        // that never comes.
        var teardownRan = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            // After teardown clears the gate, the relaunch skips it and runs to
            // completion.
            LifecycleStep.interactive("gate", condition: { !teardownRan }) { _ in
                Text("gate")
            }
        })
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("gate") }

        await runner.teardown(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in teardownRan = true }
        })

        await runTask.value
        #expect(teardownRan)
        // The cancelled gate was treated as a drained drive, not a failure.
        #expect(runner.phase.failure == nil)
        #expect(runner.phase.isReady)
    }
}

@MainActor
struct LifecycleRunnerFailureTests {
    @Test func thrownErrorParksInFailedAndStopsSubsequentSteps() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep.work("b") { _ in throw StepError() }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        await runner.run()
        #expect(executed == ["a"])
        #expect(runner.phase.failed(at: "b"))
        #expect(runner.phase.failure?.error is StepError)
    }

    @Test func retryResumesFromFailedStep() async throws {
        var executed: [String] = []
        var shouldFail = true
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep.work("b") { _ in
                if shouldFail { throw StepError() }
                executed.append("b")
            }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        await runner.run()
        #expect(runner.phase.failed(at: "b"))
        #expect(executed == ["a"])

        shouldFail = false
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(executed == ["a", "b", "c"])
    }

    @Test func retryIsNoOpWhenNotFailed() async {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in }
        })
        await runner.run()
        runner.retry()
        #expect(runner.phase.isReady)
    }

    @Test func bridgeFailurePropagatesToFailedPhase() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.interactive("gate") { _ in Text("x") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("gate") }
        runner.phase.runningBridge?.fail(StepError())
        await task.value
        #expect(runner.phase.failed(at: "gate"))
    }
}

@MainActor
struct LifecycleRunnerInteractiveTests {
    @Test func interactiveStepSuspendsUntilResolved() async throws {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed.append("a") }
            LifecycleStep.interactive("gate") { _ in Text("gate") }
            LifecycleStep.work("c") { _ in executed.append("c") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("gate") }
        #expect(executed == ["a"])
        #expect(!runner.phase.isReady)

        runner.phase.runningBridge?.complete()
        await task.value
        #expect(executed == ["a", "c"])
        #expect(runner.phase.isReady)
    }

    @Test func alwaysPresentationActivatesImmediately() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.interactive("ui") { _ in Text("ui") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("ui") }
        #expect(runner.phase.runningBridge?.presentation != nil)
        runner.phase.runningBridge?.complete()
        await task.value
    }

    @Test func whenFalsePresentationStaysSilent() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("s") { bridge in try await bridge.waitForResolution() }
                .presenting(when: { false }) { _ in Text("x") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("s") }
        #expect(runner.phase.runningBridge?.presentation == nil)
        runner.phase.runningBridge?.complete()
        await task.value
    }

    @Test func deferredPresentationActivatesAfterDelay() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("slow") { bridge in try await bridge.waitForResolution() }
                .presenting(after: .milliseconds(20)) { _ in Text("x") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("slow") }
        try await waitUntil { runner.phase.runningBridge?.presentation != nil }
        runner.phase.runningBridge?.complete()
        await task.value
    }

    @Test func minVisibleHoldsADeferredPresentationAfterTheStepFinishes() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("slow") { bridge in try await bridge.waitForResolution() }
                .presenting(after: .milliseconds(10), minVisible: .milliseconds(300)) { _ in
                    Text("x")
                }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("slow") }
        try await waitUntil { runner.phase.runningBridge?.presentation != nil }

        // Finish the step right after the deferred UI appeared; minVisible must
        // keep the runner from reaching .ready until the hold window elapses.
        let shownAt = ContinuousClock.now
        runner.phase.runningBridge?.complete()
        try await waitUntil(timeout: .seconds(2)) { runner.phase.isReady }
        #expect(shownAt.duration(to: .now) >= .milliseconds(200))
        await task.value
    }

    @Test func progressIsReadableWhileStepRuns() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.interactive("p", perform: { bridge in
                bridge.progress = 0.5
                try await bridge.waitForResolution()
            }) { _ in Text("p") }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("p") }
        #expect(runner.phase.runningBridge?.progress == 0.5)
        runner.phase.runningBridge?.complete()
        await task.value
    }
}
