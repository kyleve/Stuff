@_spi(Testing) @testable import LifecycleKit
import SwiftUI
import Testing

private struct StepError: Error {}

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
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        // Promotion re-drives from the top, but the already-completed unrestricted
        // step is skipped (run-once); only the now-applicable foreground-only step
        // runs.
        #expect(executed == ["store", "onboarding"])
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)
    }

    @Test func undeterminedLaunchRunsBackgroundStepsThenPromotesToForeground() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .undetermined, sequence: LifecycleSteps {
            LifecycleStep.work("store") { _ in executed.append("store") }
            LifecycleStep
                .work("onboarding", modes: .foreground) { _ in executed.append("onboarding") }
        })
        await runner.run()
        // Undetermined gates to the background-safe subset: the foreground-only
        // step is skipped and the host builds no view tree.
        #expect(executed == ["store"])
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        // A scene activated: the launch resolves to foreground and the
        // foreground-only step runs. The already-completed "store" is skipped
        // (run-once), so it doesn't run a second time.
        #expect(executed == ["store", "onboarding"])
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.reason == .userForeground)
        #expect(runner.phase.isReady)
    }

    @Test func retryAfterPromotionSkipsAStepAlreadyCompletedInTheHeadlessDrive() async throws {
        // Run-once spans a promotion + a `retry()` within the same attempt: a
        // later step that already completed during the headless drive must not
        // re-run when `retry()` resumes from an *earlier* foreground-only step
        // that failed on promotion.
        var executed: [String] = []
        var onboardingShouldFail = true
        let runner = LifecycleRunner(reason: .undetermined, sequence: LifecycleSteps {
            LifecycleStep.work("store") { _ in executed.append("store") }
            LifecycleStep.work("onboarding", modes: .foreground) { _ in
                executed.append("onboarding")
                if onboardingShouldFail { throw StepError() }
            }
            LifecycleStep.work("widget") { _ in executed.append("widget") }
        })

        // Headless drive: the background-safe "store" and "widget" complete; the
        // foreground-only "onboarding" (index between them) is skipped.
        await runner.run()
        #expect(executed == ["store", "widget"])
        #expect(runner.phase.isReady)

        // Promotion re-drives from the top: "store" is skipped (completed), the
        // now-applicable "onboarding" runs and fails.
        await runner.enterForeground()
        #expect(runner.phase.failed(at: "onboarding"))
        #expect(executed == ["store", "widget", "onboarding"])

        // Retry resumes from the failed "onboarding" (now succeeds). "widget",
        // which sits *after* it but already completed in the headless drive, is
        // skipped rather than run a second time.
        onboardingShouldFail = false
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(executed == ["store", "widget", "onboarding", "onboarding"])
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

    @Test func backgroundWorkStepCallingWaitForResolutionDoesNotReachReadyUntilPromoted(
    ) async throws {
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep.work("wait") { bridge in try await bridge.waitForResolution() }
        })
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("wait") }

        // Regression: a background `.work` step parked on `waitForResolution()`
        // must not drain to `.ready` while still headless — there is no UI to
        // resolve it.
        try await Task.sleep(for: .milliseconds(50))
        #expect(runner.reason.buildsNoViewTree)
        #expect(runner.phase.isRunning("wait"))

        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { !runner.reason.buildsNoViewTree }
        runner.phase.runningBridge?.complete()
        await runTask.value
        await promote.value
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
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)
    }

    @Test func supersededDriveThatThrowsDoesNotClobberThePromotedDrivesPhase() async throws {
        // A superseded drive's in-flight step isn't required to be
        // cancellation-responsive: it can keep working after the promotion
        // cancels its drive and then throw a *real* error (the fresh-install
        // store-open failure did exactly this). That dying drive must not park
        // the runner in `.failed` — the promoted drive owns the phase and
        // re-runs the step itself.
        let (blockedStep, releaseBlockedStep) = AsyncStream.makeStream(of: Void.self)
        let (gatedCondition, releaseGatedCondition) = AsyncStream.makeStream(of: Void.self)
        var attempts = 0
        var conditionChecks = 0
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {
            LifecycleStep(
                id: "store",
                condition: {
                    conditionChecks += 1
                    if conditionChecks > 1 {
                        // Hold the promoted drive here — before it publishes
                        // any phase of its own — so the test can observe what
                        // the dying drive left behind.
                        for await _ in gatedCondition {}
                    }
                    return true
                },
            ) { _ in
                attempts += 1
                if attempts == 1 {
                    // Park until released, then fail for real — after the
                    // promotion has already superseded this drive.
                    for await _ in blockedStep {}
                    throw StepError()
                }
            }
        })

        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("store") }

        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { !runner.reason.buildsNoViewTree }

        // Let the superseded drive's step throw now that the promotion owns
        // the phase, and wait for the promoted drive to reach the gated
        // condition (which it only does after fully draining the dying drive).
        releaseBlockedStep.finish()
        try await waitUntil { conditionChecks > 1 }
        #expect(runner.phase.failure == nil)

        releaseGatedCondition.finish()
        await promote.value
        await runTask.value
        #expect(attempts == 2)
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

    @Test func retryIsNoOpWhenFailedStepIDDoesNotMatchAnyStep() async {
        var executed = 0
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in executed += 1 }
        })
        await runner.run()
        #expect(runner.phase.isReady)

        runner.injectFailureForTesting(LifecycleFailure(stepID: "missing", error: StepError()))
        runner.retry()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(runner.phase.failed(at: "missing"))
        #expect(executed == 1)
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

    @Test func minVisibleHoldsAnAlwaysPresentationAfterAFastStep() async {
        // minVisible is unified across triggers: an `.always` presentation on a
        // step that does no async work must still stay up for its hold window
        // before the runner reaches .ready, just like the deferred path.
        let startedAt = ContinuousClock.now
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("fast") { _ in }
                .presenting(minVisible: .milliseconds(300)) { _ in Text("x") }
        })
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(startedAt.duration(to: .now) >= .milliseconds(200))
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
