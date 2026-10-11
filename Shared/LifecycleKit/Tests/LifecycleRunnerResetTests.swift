@testable import LifecycleKit
import Testing

private struct ResetError: Error {}

@MainActor
struct LifecycleRunnerResetTests {
    @Test func teardownCanIdentifyAndDrainASuspendedGateCheck() async throws {
        let dependency = LifecycleOperationGate()
        var retired = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureGate<Void>("onboarding") { _ in
                if retired { return false }
                await dependency.wait()
                return true
            }),
        )
        let drive = Task { await runner.run() }
        try await waitUntil { dependency.entered }
        #expect(runner.phase.isRunning("onboarding"))
        let replacement = Task {
            await runner.teardown(
                LaunchPlan(FixtureStep<Void, Void>("retire") { _, _ in retired = true }),
                input: (),
            )
        }
        try await waitUntil { dependency.cancelled }
        #expect(!retired)
        dependency.release()
        await replacement.value
        await drive.value
        #expect(retired)
        #expect(runner.phase.isReady)
    }

    @Test func teardownRunsThenRelaunchesWithItsTypedInput() async {
        var events: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("launch") { _, _ in
                events.append("launch")
                return "session"
            }),
        )
        await runner.run()
        #expect(events == ["launch"])
        #expect(runner.phase.isReady)

        // The teardown plan roots at a real value — the thing being torn down.
        await runner.teardown(
            LaunchPlan(FixtureStep<String, Void>("teardown") { value, _ in
                events.append("teardown-\(value)")
            }),
            input: "session",
        )
        #expect(events == ["launch", "teardown-session", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func teardownNodesRunInOrder() async {
        var events: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("noop") { _, _ in }),
        )
        await runner.run()

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("stop-gps") { _, _ in events.append("stop-gps") })
                .thenKeeping(FixtureStep<Void, Void>("clear-store") { _, _ in
                    events.append("clear-store")
                })
                .thenKeeping(FixtureStep<Void, Void>("clear-widget") { _, _ in
                    events.append("clear-widget")
                }),
            input: (),
        )
        #expect(events == ["stop-gps", "clear-store", "clear-widget"])
    }

    @Test func teardownGateParksAndResumes() async throws {
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("noop") { _, _ in }),
        )
        await runner.run()

        let task = Task { @MainActor in
            await runner.teardown(
                LaunchPlan(FixtureStep<Void, String>("prepare") { _, _ in "account" })
                    .gate(FixtureGate<String>("signing-out")),
                input: (),
            )
        }
        try await waitUntil { runner.phase.isAwaitingGate("signing-out") }
        #expect(runner.phase.gateHandle?.value as? String == "account")

        runner.phase.gateHandle?.complete()
        await task.value
        #expect(runner.phase.isReady)
    }

    @Test func teardownDetachedChildrenDrainBeforeTheRelaunch() async {
        var events: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("launch") { _, _ in
                events.append("launch")
            }),
        )
        await runner.run()
        events.removeAll()

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("erase") { _, _ in events.append("erase") })
                .detached {
                    FixtureStep<Void, Void>("flush") { _, _ in
                        // Yield so the trunk finishes first; the relaunch must
                        // still wait for this child — no torn-down-world work
                        // may overlap the fresh launch.
                        await Task.yield()
                        events.append("flush")
                    }
                },
            input: (),
        )
        #expect(events == ["erase", "flush", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func failedTeardownParksInFailedAndSkipsRelaunch() async {
        var relaunched = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("launch") { _, _ in relaunched = true }),
        )
        await runner.run()
        relaunched = false

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("teardown") { _, _ in throw ResetError() }),
            input: (),
        )
        #expect(runner.phase.failed(at: "teardown"))
        #expect(!relaunched)
    }

    @Test func teardownNodesMayReuseLaunchNodeIDs() async {
        // Teardown starts from an empty run-once set (the launch attempt is
        // over), so a teardown node may share a launch node's ID and still
        // run — no cross-plan disjointness precondition needed, because there
        // is no retry re-walk that would consult a live launch memo.
        var events: [String] = []
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("shared-id") { _, _ in
                events.append("launch-side")
            }),
        )
        await runner.run()

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("shared-id") { _, _ in
                events.append("teardown-side")
            }),
            input: (),
        )
        #expect(events == ["launch-side", "teardown-side", "launch-side"])
        #expect(runner.phase.isReady)
    }

    @Test func teardownCancelsAParkedGateInsteadOfHanging() async throws {
        // Without cooperative cancellation, `teardown()` would await the run
        // drive forever: it is parked on a gate waiting for a tap that never
        // comes.
        var teardownRan = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "session" })
                // After teardown clears the gate, the relaunch skips it and
                // runs to completion.
                .gate(FixtureGate<String>("gate") { _ in !teardownRan }),
        )
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("gate") }

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("teardown") { _, _ in teardownRan = true }),
            input: (),
        )

        await runTask.value
        #expect(teardownRan)
        // The cancelled gate was treated as a drained drive, not a failure.
        #expect(runner.phase.failure == nil)
        #expect(runner.phase.isReady)
    }

    @Test func teardownDrainsGateWorkBeforeRetiringAndRelaunching() async throws {
        var events: [String] = []
        let dependency = LifecycleOperationGate()
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureGate<Void>("onboarding") { _ in
                !events.contains("teardown")
            }).then(FixtureStep<Void, Void>("launch") { _, _ in events.append("launch") }),
        )
        let drive = Task { await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }
        let oldGate = try #require(runner.phase.gateHandle)
        oldGate.perform {
            await dependency.wait()
            #expect(Task.isCancelled)
            events.append("drained")
            oldGate.complete()
        }
        try await waitUntil { dependency.entered }
        let replacement = Task {
            await runner.teardown(
                LaunchPlan(FixtureStep<Void, Void>("retire") { _, _ in
                    events.append("teardown")
                }),
                input: (),
            )
        }
        try await waitUntil { dependency.cancelled }
        #expect(events.isEmpty)
        dependency.release()
        await replacement.value
        await drive.value
        #expect(events == ["drained", "teardown", "launch"])
        #expect(runner.phase.isReady)
    }
}
