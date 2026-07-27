@_spi(Testing) @testable import LifecycleKit
import Testing

private struct StepError: Error {}

@MainActor
struct LifecycleRunnerDriveTests {
    @Test func runsTrunkNodesInDeclarationOrderAndThreadsTheValue() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Int>("open") { _, _ in
                executed.append("open")
                return 41
            })
            .then(FixtureStep<Int, Int>("increment") { value, _ in
                executed.append("increment")
                return value + 1
            })
            .thenKeeping(FixtureStep<Int, Void>("keep") { value, _ in
                executed.append("keep-\(value)")
            }),
        )
        await runner.run()
        #expect(executed == ["open", "increment", "keep-42"])
        #expect(runner.phase.isReady)
        // .ready carries the trunk's output — the app's input.
        #expect(runner.phase.readyValue == 42)
    }

    @Test func filtersPassThroughNodesByLaunchReason() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in
                executed.append("root")
                return "session"
            })
            .thenKeeping(FixtureStep<String, Void>("always") { _, _ in executed.append("always") })
            .thenKeeping(FixtureStep<String, Void>("fg", modes: .foreground) { _, _ in
                executed.append("fg")
            })
            .thenKeeping(FixtureStep<String, Void>("bg", modes: .background) { _, _ in
                executed.append("bg")
            }),
        )
        await runner.run()
        #expect(executed == ["root", "always", "bg"])
        #expect(runner.phase.isReady)
    }

    @Test func gatesAreSkippedInBackground() async {
        // Gates default to .foreground: a headless launch skips them (and
        // never deadlocks waiting for a tap that can't come).
        var evaluated = false
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding") { _ in
                    evaluated = true
                    return true
                }),
        )
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(!evaluated)
    }

    @Test func runIsIdempotent() async {
        var count = 0
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("a") { _, _ in count += 1 }),
        )
        await runner.run()
        await runner.run()
        #expect(count == 1)
    }
}

@MainActor
struct LifecycleRunnerDetachedTests {
    @Test func detachedChildrenDoNotBlockReady() async throws {
        let (parked, release) = AsyncStream.makeStream(of: Void.self)
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .detached {
                    FixtureStep<String, Void>("slow") { _, _ in
                        for await _ in parked {}
                    }
                },
        )
        let task = Task { @MainActor in await runner.run() }
        // .ready is published as soon as the trunk finishes, while the child
        // is still parked.
        try await waitUntil { runner.phase.isReady }
        release.finish()
        await task.value
        #expect(runner.phase.readyValue == "session")
    }

    @Test func detachedChildrenReceiveTheTrunkValue() async {
        var seen: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .detached {
                    FixtureStep<String, Void>("child") { value, _ in seen.append(value) }
                },
        )
        await runner.run()
        #expect(seen == ["session"])
    }

    @Test func detachedFailureIsRecordedButNeverFatal() async {
        var ran = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .detached {
                    FixtureStep<String, Void>("boom") { _, _ in throw StepError() }
                    FixtureStep<String, Void>("fine") { _, _ in ran = true }
                },
        )
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(ran)
        #expect(runner.detachedFailures.map(\.stepID) == [AnyHashable("boom")])
        #expect(runner.detachedFailures.first?.error is StepError)
    }

    @Test func detachedChildrenHonorModeGating() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .detached {
                    FixtureStep<String, Void>("fg", modes: .foreground) { _, _ in
                        executed.append("fg")
                    }
                    FixtureStep<String, Void>("bg", modes: .background) { _, _ in
                        executed.append("bg")
                    }
                },
        )
        await runner.run()
        #expect(executed == ["bg"])
    }
}

@MainActor
struct LifecycleRunnerGateTests {
    @Test func gateParksTheTrunkUntilResolved() async throws {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in
                executed.append("root")
                return "session"
            })
            .gate(FixtureGate<String>("onboarding"))
            .thenKeeping(FixtureStep<String, Void>("after") { _, _ in executed.append("after") }),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        #expect(executed == ["root"])
        #expect(!runner.phase.isReady)

        runner.phase.gateHandle?.complete()
        await task.value
        #expect(executed == ["root", "after"])
        #expect(runner.phase.isReady)
    }

    @Test func gateEvaluatesIsNeededAgainstTheTrunkValue() async {
        var seen: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding") { value in
                    seen.append(value)
                    return false
                }),
        )
        await runner.run()
        // Not needed → skipped, the value flows through, no park.
        #expect(runner.phase.readyValue == "session")
        #expect(seen == ["session"])
    }

    @Test func gateFailurePropagatesToFailedPhase() async throws {
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding")),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        runner.phase.gateHandle?.fail(StepError())
        await task.value
        #expect(runner.phase.failed(at: "onboarding"))
    }

    @Test func gateHandleCarriesTheGateTypeAndValueForTheRegistry() async throws {
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding")),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        let handle = try #require(runner.phase.gateHandle)
        #expect(handle.gateType == ObjectIdentifier(FixtureGate<String>.self))
        #expect(handle.value as? String == "session")
        handle.complete()
        await task.value
    }

    @Test func contextProgressIsReadableWhileAStepRuns() async throws {
        let (parked, release) = AsyncStream.makeStream(of: Void.self)
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, context in
                context.progress = 0.5
                context.message = "opening"
                for await _ in parked {}
                return "session"
            }),
        )
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
    @Test func enterForegroundReDrivesAndRunsForegroundOnlyNodes() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("store") { _, _ in
                executed.append("store")
                return "session"
            })
            .thenKeeping(FixtureStep<String, Void>("onboarding", modes: .foreground) { _, _ in
                executed.append("onboarding")
            }),
        )
        await runner.run()
        // The headless background drive ran only the unrestricted node.
        #expect(executed == ["store"])
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        // Promotion re-drives from the top, but the already-completed
        // unrestricted node is skipped (memoized); only the now-applicable
        // foreground-only node runs.
        #expect(executed == ["store", "onboarding"])
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)
    }

    @Test func undeterminedLaunchRunsBackgroundNodesThenPromotesToForeground() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .undetermined,
            plan: LaunchPlan(FixtureStep<Void, String>("store") { _, _ in
                executed.append("store")
                return "session"
            })
            .thenKeeping(FixtureStep<String, Void>("onboarding", modes: .foreground) { _, _ in
                executed.append("onboarding")
            }),
        )
        await runner.run()
        // Undetermined gates to the background-safe subset: the foreground-only
        // node is skipped and the host builds no view tree.
        #expect(executed == ["store"])
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        #expect(executed == ["store", "onboarding"])
        #expect(runner.reason == .userForeground)
        #expect(runner.phase.isReady)
    }

    @Test func promotionReEvaluatesAGateSkippedHeadless() async throws {
        // A gate skipped during the headless drive is *not* memoized: once a
        // scene promotes the launch, the re-drive parks on it.
        let runner = LifecycleRunner(
            reason: .undetermined,
            plan: LaunchPlan(FixtureStep<Void, String>("store") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding")),
        )
        await runner.run()
        #expect(runner.phase.isReady)

        let promote = Task { @MainActor in await runner.enterForeground() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        runner.phase.gateHandle?.complete()
        await promote.value
        #expect(runner.phase.isReady)
    }

    @Test func promotionSkipsNodesCompletedInTheHeadlessDrive() async {
        // Run-once spans the headless drive and the promotion re-drive: a node
        // that already completed while headless must not re-run when
        // `enterForeground()` re-drives from the top for the now-applicable
        // foreground-only node.
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .undetermined,
            plan: LaunchPlan(FixtureStep<Void, String>("store") { _, _ in
                executed.append("store")
                return "session"
            })
            .thenKeeping(FixtureStep<String, Void>("onboarding", modes: .foreground) { _, _ in
                executed.append("onboarding")
            })
            .thenKeeping(FixtureStep<String, Void>("widget") { _, _ in
                executed.append("widget")
            }),
        )

        // Headless drive: the background-safe "store" and "widget" complete;
        // the foreground-only "onboarding" (between them) is skipped.
        await runner.run()
        #expect(executed == ["store", "widget"])
        #expect(runner.phase.isReady)

        // Promotion re-drives from the top: "store" and "widget" are skipped
        // (memoized), only the now-applicable "onboarding" runs.
        await runner.enterForeground()
        #expect(executed == ["store", "widget", "onboarding"])
        #expect(runner.phase.isReady)
    }

    @Test func enterForegroundIsNoOpForAForegroundLaunch() async {
        var count = 0
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("a") { _, _ in count += 1 }),
        )
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
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("slow") { _, _ in
                starts += 1
                inFlight += 1
                defer { inFlight -= 1 }
                maxInFlight = max(maxInFlight, inFlight)
                // Park on a cancellation-aware wait the test resolves.
                let handle = LifecycleGateHandle(id: "park-\(starts)", reason: .userForeground)
                handles.append(handle)
                try await handle.waitForResolution()
                return "session"
            }),
        )
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("slow") }

        // Promote while the background drive is parked in "slow". Promotion
        // cancels that drive (its wait throws), drains it, and only then
        // re-drives "slow" for the foreground launch — never two at once.
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
        let runner = LifecycleRunner(
            reason: .background(.location),
            plan: LaunchPlan(FixtureStep<Void, String>("store") { _, _ in
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
            }),
        )

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
    @Test func thrownErrorParksInFailedAndStopsSubsequentNodes() async {
        var executed: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("a") { _, _ in
                executed.append("a")
                return "session"
            })
            .thenKeeping(FixtureStep<String, Void>("b") { _, _ in throw StepError() })
            .thenKeeping(FixtureStep<String, Void>("c") { _, _ in executed.append("c") }),
        )
        await runner.run()
        #expect(executed == ["a"])
        #expect(runner.phase.failed(at: "b"))
        #expect(runner.phase.failure?.error is StepError)
    }

    @Test func failureIsTerminalAndRunDoesNotReDrive() async {
        // No retry: once a node throws, the drive is done. A later `run()`
        // awaits the finished drive rather than starting a new one, so the
        // launch stays `.failed` and the failing node doesn't run again — the
        // recovery is relaunching the app (a fresh process, fresh runner).
        var attempts = 0
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("boom") { _, _ in
                attempts += 1
                throw StepError()
            }),
        )
        await runner.run()
        #expect(runner.phase.failed(at: "boom"))
        #expect(attempts == 1)

        await runner.run()
        #expect(runner.phase.failed(at: "boom"))
        #expect(attempts == 1)
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
