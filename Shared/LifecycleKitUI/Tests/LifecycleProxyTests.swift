import LifecycleKit
@testable import LifecycleKitUI
import Testing

@MainActor
struct LifecycleProxyTests {
    @Test func defaultProxyIsDisconnected() {
        // The environment default: nothing to drive, so callers no-op (debug
        // asserts) rather than dereferencing a missing runner.
        #expect(LifecycleProxy().base == nil)
    }

    @Test func connectedProxyForwardsTypedTeardownToTheRunner() async {
        var tornDownWith: String?
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" }),
        )
        await runner.run()
        #expect(runner.phase.isReady)

        // The typed plan + input cross the non-generic environment seam and
        // land on the runner with the value intact.
        await LifecycleProxy(runner).teardown(
            LaunchPlan(FixtureStep<String, Void>("teardown") { value, _ in
                tornDownWith = value
            }),
            input: "session",
        )
        #expect(tornDownWith == "session")
        #expect(runner.phase.isReady)
    }

    @Test func connectedProxyForwardsRetryToTheRunner() async throws {
        struct Boom: Error {}
        var shouldFail = true
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in
                if shouldFail { throw Boom() }
                return "session"
            }),
        )
        await runner.run()
        #expect(runner.phase.failed(at: "open"))

        shouldFail = false
        LifecycleProxy(runner).retry()
        try await waitUntil { runner.phase.isReady }
    }
}
