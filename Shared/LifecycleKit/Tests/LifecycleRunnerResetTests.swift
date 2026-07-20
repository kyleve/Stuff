@testable import LifecycleKit
import Testing

private struct ResetError: Error {}

@MainActor
struct LifecycleRunnerResetTests {
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

    @Test func retryAfterFailedTeardownReRunsTeardownThenRelaunches() async throws {
        var events: [String] = []
        var shouldFailErase = true
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("launch") { _, _ in events.append("launch") }),
        )
        await runner.run()
        events.removeAll()

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("erase") { _, _ in
                events.append("erase")
                if shouldFailErase { throw ResetError() }
            })
            .thenKeeping(FixtureStep<Void, Void>("clear-prefs") { _, _ in
                events.append("clear-prefs")
            }),
            input: (),
        )
        #expect(runner.phase.failed(at: "erase"))
        #expect(events == ["erase"])

        // Retry must resume the teardown (re-erasing) and only then relaunch —
        // not silently re-drive the launch plan over un-torn-down state.
        shouldFailErase = false
        events.removeAll()
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(events == ["erase", "clear-prefs", "launch"])
    }

    @Test func retryAfterFailedTeardownTailResumesWithoutReErasing() async throws {
        var events: [String] = []
        var shouldFailPrefs = true
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, Void>("launch") { _, _ in events.append("launch") }),
        )
        await runner.run()
        events.removeAll()

        await runner.teardown(
            LaunchPlan(FixtureStep<Void, Void>("erase") { _, _ in events.append("erase") })
                .thenKeeping(FixtureStep<Void, Void>("clear-prefs") { _, _ in
                    events.append("clear-prefs")
                    if shouldFailPrefs { throw ResetError() }
                }),
            input: (),
        )
        #expect(runner.phase.failed(at: "clear-prefs"))
        #expect(events == ["erase", "clear-prefs"])

        // The earlier teardown node ("erase") already succeeded, so retry
        // resumes from the failed node rather than re-running it, then
        // relaunches.
        shouldFailPrefs = false
        events.removeAll()
        runner.retry()
        try await waitUntil { runner.phase.isReady }
        #expect(events == ["clear-prefs", "launch"])
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
}
