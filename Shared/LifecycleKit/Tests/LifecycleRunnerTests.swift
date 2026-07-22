@_spi(Testing) @testable import LifecycleKit
import Testing

private struct StepError: Error {}

@MainActor
struct LifecycleRunnerDriveTests {
    @Test func runsStepsInOrderAndThreadsValuesThroughLets() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let opened: Int = try await context.step("open") {
                executed.append("open")
                return 41
            }
            let incremented: Int = try await context.step("increment") {
                executed.append("increment")
                return opened + 1
            }
            try await context.step("keep") {
                executed.append("keep-\(incremented)")
            }
            return incremented
        }
        await runner.run()
        #expect(executed == ["open", "increment", "keep-42"])
        #expect(runner.phase.isReady)
        // .ready carries the function's return value — the app's input.
        #expect(runner.phase.readyValue == 42)
    }

    @Test func filtersVoidStepsByLaunchReason() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            let root: String = try await context.step("root") {
                executed.append("root")
                return "session"
            }
            try await context.step("always") { executed.append("always") }
            try await context.step("fg", modes: .foreground) { executed.append("fg") }
            try await context.step("bg", modes: .background) { executed.append("bg") }
            return root
        }
        await runner.run()
        #expect(executed == ["root", "always", "bg"])
        #expect(runner.phase.isReady)
    }

    @Test func gatesAreSkippedInBackground() async {
        // Gates default to .foreground: a headless launch skips them (and
        // never deadlocks waiting for a tap that can't come).
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            let root: String = try await context.step("root") { "session" }
            try await context.gate(FixtureGate<String>("onboarding"), value: root)
            return root
        }
        await runner.run()
        #expect(runner.phase.isReady)
    }

    @Test func runIsIdempotent() async {
        var count = 0
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("a") { count += 1 }
        }
        await runner.run()
        await runner.run()
        #expect(count == 1)
    }

    @Test func recordsExecutedStepIDsInOrder() async {
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            try await context.step("keep") {}
            try await context.step("skipped", modes: .background) {}
            context.detached("fan") {}
            return root
        }
        await runner.run()
        // The function style has no inspectable node list; executed-ID
        // recording is the replacement for order-style assertions. Skipped
        // (mode-gated) steps don't appear.
        #expect(runner.executedStepIDs == ["root", "keep", "fan"])
    }

    @Test func bareGlueReRunsOnReDrivesButMemoizedStepsDoNot() async {
        // THE discipline of the function style: bare code between steps
        // re-runs on every re-drive (promotion here), while completed steps
        // skip via the memo. Effects belong inside steps.
        var glueRuns = 0
        var stepRuns = 0
        let runner = LifecycleRunner(reason: .undetermined) { context in
            glueRuns += 1
            return try await context.step("root") {
                stepRuns += 1
                return "session"
            }
        }
        await runner.run()
        await runner.enterForeground()
        #expect(glueRuns == 2)
        #expect(stepRuns == 1)
        #expect(runner.phase.isReady)
    }
}

@MainActor
struct LifecycleRunnerDetachedTests {
    @Test func detachedWorkDoesNotBlockReady() async throws {
        let (parked, release) = AsyncStream.makeStream(of: Void.self)
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            context.detached("slow") {
                for await _ in parked {}
            }
            return root
        }
        let task = Task { @MainActor in await runner.run() }
        // .ready is published as soon as the function returns, while the
        // detached work is still parked.
        try await waitUntil { runner.phase.isReady }
        release.finish()
        await task.value
        #expect(runner.phase.readyValue == "session")
    }

    @Test func detachedWorkCapturesTheValuesItNeeds() async {
        var seen: [String] = []
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            context.detached("child") { seen.append(root) }
            return root
        }
        await runner.run()
        #expect(seen == ["session"])
    }

    @Test func detachedFailureIsRecordedButNeverFatal() async {
        var ran = false
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            context.detached("boom") { throw StepError() }
            context.detached("fine") { ran = true }
            return root
        }
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(ran)
        #expect(runner.detachedFailures.map(\.stepID) == [AnyHashable("boom")])
        #expect(runner.detachedFailures.first?.error is StepError)
    }

    @Test func detachedWorkHonorsModeGating() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            let root: String = try await context.step("root") { "session" }
            context.detached("fg", modes: .foreground) { executed.append("fg") }
            context.detached("bg", modes: .background) { executed.append("bg") }
            return root
        }
        await runner.run()
        #expect(executed == ["bg"])
    }
}

@MainActor
struct LifecycleRunnerGateTests {
    /// A launch function with a root step, a gate, and a step after the gate
    /// — the shape most gate tests need.
    private func makeGatedRunner(
        reason: LifecycleReason = .userForeground,
        after: @escaping @MainActor () -> Void = {},
    ) -> LifecycleRunner<String> {
        LifecycleRunner(reason: reason) { context in
            let root: String = try await context.step("root") { "session" }
            try await context.gate(FixtureGate<String>("onboarding"), value: root)
            try await context.step("after") { after() }
            return root
        }
    }

    @Test func gateParksTheFunctionUntilResolved() async throws {
        var afterRan = false
        let runner = makeGatedRunner { afterRan = true }
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        #expect(!afterRan)
        #expect(!runner.phase.isReady)

        runner.phase.gateHandle?.complete()
        await task.value
        #expect(afterRan)
        #expect(runner.phase.isReady)
    }

    @Test func gateFailurePropagatesToFailedPhase() async throws {
        let runner = makeGatedRunner()
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        runner.phase.gateHandle?.fail(StepError())
        await task.value
        #expect(runner.phase.failed(at: "onboarding"))
    }

    @Test func gateHandleCarriesTheGateTypeAndValueForTheRegistry() async throws {
        let runner = makeGatedRunner()
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        let handle = try #require(runner.phase.gateHandle)
        #expect(handle.gateType == ObjectIdentifier(FixtureGate<String>.self))
        #expect(handle.value as? String == "session")
        handle.complete()
        await task.value
    }

    @Test func runningStepContextIsReadableWhileAStepRuns() async throws {
        let (parked, release) = AsyncStream.makeStream(of: Void.self)
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("root") {
                context.runningStep?.progress = 0.5
                context.runningStep?.message = "opening"
                for await _ in parked {}
                return "session"
            }
        }
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("root") }
        #expect(runner.phase.runningContext?.progress == 0.5)
        #expect(runner.phase.runningContext?.message == "opening")
        release.finish()
        await task.value
        #expect(runner.phase.isReady)
    }
}

@MainActor
struct LifecycleRunnerForegroundPromotionTests {
    @Test func enterForegroundReRunsAndExecutesForegroundOnlySteps() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            let store: String = try await context.step("store") {
                executed.append("store")
                return "session"
            }
            try await context.step("onboarding", modes: .foreground) {
                executed.append("onboarding")
            }
            return store
        }
        await runner.run()
        // The headless background drive ran only the unrestricted step.
        #expect(executed == ["store"])
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        // Promotion re-runs the function, but the already-completed
        // unrestricted step is skipped (memoized); only the now-applicable
        // foreground-only step runs.
        #expect(executed == ["store", "onboarding"])
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)
    }

    @Test func undeterminedLaunchRunsBackgroundStepsThenPromotesToForeground() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .undetermined) { context in
            let store: String = try await context.step("store") {
                executed.append("store")
                return "session"
            }
            try await context.step("onboarding", modes: .foreground) {
                executed.append("onboarding")
            }
            return store
        }
        await runner.run()
        #expect(executed == ["store"])
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        #expect(executed == ["store", "onboarding"])
        #expect(runner.reason == .userForeground)
        #expect(runner.phase.isReady)
    }

    @Test func promotionReEvaluatesAGateSkippedHeadless() async throws {
        // A gate skipped during the headless drive is *not* memoized: once a
        // scene promotes the launch, the re-run parks on it.
        let runner = LifecycleRunner(reason: .undetermined) { context in
            let root: String = try await context.step("store") { "session" }
            try await context.gate(FixtureGate<String>("onboarding"), value: root)
            return root
        }
        await runner.run()
        #expect(runner.phase.isReady)

        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        runner.phase.gateHandle?.complete()
        await promote.value
        #expect(runner.phase.isReady)
    }

    @Test func retryAfterPromotionSkipsAStepAlreadyCompletedInTheHeadlessDrive() async throws {
        // Run-once spans a promotion + a `retry()` within the same attempt: a
        // later step that already completed during the headless drive must not
        // re-run when `retry()` re-runs the function after an *earlier*
        // foreground-only step failed on promotion.
        var executed: [String] = []
        var onboardingShouldFail = true
        let runner = LifecycleRunner(reason: .undetermined) { context in
            let store: String = try await context.step("store") {
                executed.append("store")
                return "session"
            }
            try await context.step("onboarding", modes: .foreground) {
                executed.append("onboarding")
                if onboardingShouldFail { throw StepError() }
            }
            try await context.step("widget") { executed.append("widget") }
            return store
        }

        // Headless drive: the background-safe "store" and "widget" complete;
        // the foreground-only "onboarding" (between them) is skipped.
        await runner.run()
        #expect(executed == ["store", "widget"])
        #expect(runner.phase.isReady)

        // Promotion re-runs the function: "store" is skipped (memoized), the
        // now-applicable "onboarding" runs and fails.
        await runner.enterForeground()
        #expect(runner.phase.failed(at: "onboarding"))
        #expect(executed == ["store", "widget", "onboarding"])

        // Retry re-runs the function; "onboarding" (unmemoized) re-runs and
        // succeeds, while "widget" — after it, but completed in the headless
        // drive — is skipped rather than run a second time.
        onboardingShouldFail = false
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(executed == ["store", "widget", "onboarding", "onboarding"])
    }

    @Test func enterForegroundIsNoOpForAForegroundLaunch() async {
        var count = 0
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("a") { count += 1 }
        }
        await runner.run()
        await runner.enterForeground()
        #expect(count == 1)
        #expect(runner.phase.isReady)
    }

    @Test func enterForegroundCancelsAndDrainsAnInFlightBackgroundDrive() async throws {
        var starts = 0
        var inFlight = 0
        var maxInFlight = 0
        var handles: [LifecycleGateHandle] = []
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            try await context.step("slow") {
                starts += 1
                inFlight += 1
                defer { inFlight -= 1 }
                maxInFlight = max(maxInFlight, inFlight)
                // Park on a cancellation-aware wait the test resolves.
                let handle = LifecycleGateHandle(id: "park-\(starts)", reason: .userForeground)
                handles.append(handle)
                try await handle.waitForResolution()
                return "session"
            }
        }
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("slow") }

        // Promote while the background drive is parked in "slow". Promotion
        // cancels that drive (its wait throws), drains it, and only then
        // re-runs "slow" for the foreground launch — never two at once.
        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { starts == 2 }

        handles.last?.complete()
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
        let (blockedFirst, _) = AsyncStream.makeStream(of: Void.self)
        let (blockedSecond, releaseSecond) = AsyncStream.makeStream(of: Void.self)
        var attempts = 0
        let runner = LifecycleRunner(reason: .background(.location)) { context in
            try await context.step("store") {
                attempts += 1
                if attempts == 1 {
                    // Parks until the promotion cancels this drive (the
                    // stream iteration ends on cancellation), then fails for
                    // real — after the promotion has superseded it.
                    for await _ in blockedFirst {}
                    throw StepError()
                }
                for await _ in blockedSecond {}
                return "session"
            }
        }

        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("store") }

        let promote = Task { @MainActor in await runner.enterForeground() }
        // The promoted drive only reaches its attempt after fully draining the
        // dying drive — whose real error must have been discarded.
        try await waitUntil { attempts == 2 }
        #expect(runner.phase.failure == nil)

        releaseSecond.finish()
        await promote.value
        await runTask.value
        #expect(attempts == 2)
        #expect(runner.phase.isReady)
    }
}

@MainActor
struct LifecycleRunnerFailureTests {
    @Test func thrownErrorParksInFailedAndStopsSubsequentSteps() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("a") {
                executed.append("a")
                return "session"
            }
            try await context.step("b") { throw StepError() }
            try await context.step("c") { executed.append("c") }
            return root
        }
        await runner.run()
        #expect(executed == ["a"])
        #expect(runner.phase.failed(at: "b"))
        #expect(runner.phase.failure?.error is StepError)
    }

    @Test func retryReRunsTheFunctionAndResumesTheFailedStepWithItsMemoizedInput() async throws {
        var rootRuns = 0
        var received: [Int] = []
        var shouldFail = true
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: Int = try await context.step("root") {
                rootRuns += 1
                return 42
            }
            return try await context.step("flaky") {
                received.append(root)
                if shouldFail { throw StepError() }
                return root + 1
            }
        }
        await runner.run()
        #expect(runner.phase.failed(at: "flaky"))

        shouldFail = false
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        // The root ran once (memo); the retried step saw the same input.
        #expect(rootRuns == 1)
        #expect(received == [42, 42])
        #expect(runner.phase.readyValue == 43)
    }

    @Test func vanillaConditionsReEvaluateOnRetry() async throws {
        // A deliberate semantic difference from a resume-at-index engine:
        // retry re-runs the whole function, so plain `if`s before the failed
        // step re-evaluate against current state.
        var includeExtra = false
        var executed: [String] = []
        var shouldFail = true
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            if includeExtra {
                try await context.step("extra") { executed.append("extra") }
            }
            try await context.step("flaky") {
                executed.append("flaky")
                if shouldFail { throw StepError() }
            }
            return root
        }
        await runner.run()
        #expect(runner.phase.failed(at: "flaky"))
        #expect(executed == ["flaky"])

        includeExtra = true
        shouldFail = false
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(executed == ["flaky", "extra", "flaky"])
    }

    @Test func aThrowOutsideAnyStepFailsAtTheFunctionID() async {
        // Bare glue failed — attributed to the function itself so the
        // failure is visible even without step discipline.
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            if root == "session" { throw StepError() }
            return root
        }
        await runner.run()
        #expect(runner.phase.failed(at: LifecycleFunctionID.launch))
        #expect(runner.phase.failure?.error is StepError)
    }

    @Test func retryIsNoOpWhenNotFailed() async {
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("a") {}
        }
        await runner.run()
        runner.retry()
        #expect(runner.phase.isReady)
    }

    @Test func retryIsNoOpForAnInjectedFailureWithNoFailedSite() async {
        var executed = 0
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("a") { executed += 1 }
        }
        await runner.run()
        #expect(runner.phase.isReady)

        runner.injectFailureForTesting(LifecycleFailure(stepID: "missing", error: StepError()))
        runner.retry()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(runner.phase.failed(at: "missing"))
        #expect(executed == 1)
    }
}

@MainActor
struct LifecycleRunnerPhaseTests {
    private typealias Phase = LifecycleRunner<String>.Phase

    @Test func launchingAndRunningCollapseToTheSplashSurface() {
        let running = Phase.running(LifecycleStepContext(stepID: "a", reason: .userForeground))
        #expect(Phase.launching.surfaceIdentity == .splash)
        #expect(running.surfaceIdentity == .splash)
    }

    @Test func gateFailureAndReadyAreDistinctSurfaces() {
        let gate = Phase.awaitingGate(LifecycleGateHandle(id: "g", reason: .userForeground))
        let failed = Phase.failed(LifecycleFailure(stepID: "b", error: StepError()))
        #expect(gate.surfaceIdentity == .gate("g"))
        #expect(failed.surfaceIdentity == .failed("b"))
        #expect(Phase.ready("session").surfaceIdentity == .ready)
        #expect(gate.surfaceIdentity != Phase.launching.surfaceIdentity)
    }

    @Test func helpersProjectTheActiveCase() {
        let context = LifecycleStepContext(stepID: "a", reason: .userForeground)
        #expect(Phase.running(context).isRunning("a"))
        #expect(Phase.running(context).runningStepID == AnyHashable("a"))
        #expect(Phase.ready("session").readyValue == "session")
        #expect(Phase.failed(LifecycleFailure(stepID: "b", error: StepError())).failed(at: "b"))
        #expect(Phase.launching.isLaunching)
    }
}
