@testable import LifecycleKit
import Testing

private struct ResetError: Error {}

@MainActor
struct LifecycleRunnerResetTests {
    /// A one-step launch that records into `events` and returns "session".
    private func makeRunner(recording events: @escaping @MainActor (String) -> Void)
        -> LifecycleRunner<String>
    {
        LifecycleRunner(reason: .userForeground) { context in
            try await context.step("launch") {
                events("launch")
                return "session"
            }
        }
    }

    @Test func teardownRunsThenRelaunchesWithItsTypedInput() async {
        var events: [String] = []
        let runner = makeRunner { events.append($0) }
        await runner.run()
        #expect(events == ["launch"])
        #expect(runner.phase.isReady)

        // The teardown function roots at a real value — the thing being torn
        // down — captured into the closure with its type intact.
        await runner.teardown(input: "session") { value, context in
            try await context.step("teardown") {
                events.append("teardown-\(value)")
            }
        }
        #expect(events == ["launch", "teardown-session", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func teardownStepsRunInOrder() async {
        var events: [String] = []
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("noop") {}
        }
        await runner.run()

        await runner.teardown(input: ()) { _, context in
            try await context.step("stop-gps") { events.append("stop-gps") }
            try await context.step("clear-store") { events.append("clear-store") }
            try await context.step("clear-widget") { events.append("clear-widget") }
        }
        #expect(events == ["stop-gps", "clear-store", "clear-widget"])
    }

    @Test func teardownGateParksAndResumes() async throws {
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("noop") {}
        }
        await runner.run()

        let task = Task { @MainActor in
            await runner.teardown(input: ()) { _, context in
                let account: String = try await context.step("prepare") { "account" }
                try await context.gate(FixtureGate<String>("signing-out"), value: account)
            }
        }
        try await waitUntil { runner.phase.isAwaitingGate("signing-out") }
        #expect(runner.phase.gateHandle?.value as? String == "account")

        runner.phase.gateHandle?.complete()
        await task.value
        #expect(runner.phase.isReady)
    }

    @Test func teardownDetachedWorkDrainsBeforeTheRelaunch() async {
        var events: [String] = []
        let runner = makeRunner { events.append($0) }
        await runner.run()
        events.removeAll()

        await runner.teardown(input: ()) { _, context in
            try await context.step("erase") { events.append("erase") }
            context.detached("flush") {
                // Yield so the function returns first; the relaunch must
                // still wait for this work — no torn-down-world work may
                // overlap the fresh launch.
                await Task.yield()
                events.append("flush")
            }
        }
        #expect(events == ["erase", "flush", "launch"])
        #expect(runner.phase.isReady)
    }

    @Test func failedTeardownParksInFailedAndSkipsRelaunch() async {
        var relaunched = false
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("launch") { relaunched = true }
        }
        await runner.run()
        relaunched = false

        await runner.teardown(input: ()) { _, context in
            try await context.step("teardown") { throw ResetError() }
        }
        #expect(runner.phase.failed(at: "teardown"))
        #expect(!relaunched)
    }

    @Test func teardownCancelsAParkedGateInsteadOfHanging() async throws {
        // Without cooperative cancellation, `teardown()` would await the run
        // drive forever: it is parked on a gate waiting for a tap that never
        // comes.
        var teardownRan = false
        let runner = LifecycleRunner(reason: .userForeground) { context in
            let root: String = try await context.step("root") { "session" }
            // Vanilla conditionality: after teardown clears the flag, the
            // relaunch's re-run takes the other branch and completes.
            if !teardownRan {
                try await context.gate(FixtureGate<String>("gate"), value: root)
            }
            return root
        }
        let runTask = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("gate") }

        await runner.teardown(input: ()) { _, context in
            try await context.step("teardown") { teardownRan = true }
        }

        await runTask.value
        #expect(teardownRan)
        // The cancelled gate was treated as a drained drive, not a failure.
        #expect(runner.phase.failure == nil)
        #expect(runner.phase.isReady)
    }

    @Test func teardownStepsMayReuseLaunchStepIDs() async {
        // Launch and teardown memos are separate namespaces: a teardown step
        // sharing an ID with a completed launch step must still run (the
        // combinator engine had to precondition this collision away; separate
        // stores make it simply legal).
        var events: [String] = []
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("shared-id") { events.append("launch-side") }
        }
        await runner.run()

        await runner.teardown(input: ()) { _, context in
            try await context.step("shared-id") { events.append("teardown-side") }
        }
        #expect(events == ["launch-side", "teardown-side", "launch-side"])
        #expect(runner.phase.isReady)
    }
}
