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
        let runner = LifecycleRunner(reason: .userForeground) { context in
            try await context.step("open") { "session" }
        }
        await runner.run()
        #expect(runner.phase.isReady)

        // The typed input + body cross the non-generic environment seam and
        // land on the runner with the value intact.
        await LifecycleProxy(runner).teardown(input: "session") { value, context in
            try await context.step("teardown") {
                tornDownWith = value
            }
        }
        #expect(tornDownWith == "session")
        #expect(runner.phase.isReady)
    }

    @Test func connectedProxyForwardsEnterForegroundToTheRunner() async {
        var executed: [String] = []
        let runner = LifecycleRunner(reason: .undetermined) { context in
            let root: String = try await context.step("store") {
                executed.append("store")
                return "session"
            }
            try await context.step("foreground-only", modes: .foreground) {
                executed.append("foreground-only")
            }
            return root
        }
        await runner.run()
        #expect(executed == ["store"])

        await LifecycleProxy(runner).enterForeground()
        #expect(executed == ["store", "foreground-only"])
        #expect(runner.phase.isReady)
    }
}
