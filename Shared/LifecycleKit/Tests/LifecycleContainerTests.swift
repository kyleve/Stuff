@testable import LifecycleKit
import SwiftUI
import Testing
import WhereTesting

private struct ProbeError: LocalizedError {
    var errorDescription: String? {
        "probe failure"
    }
}

/// A leaf view that runs `mark` when the host lays it out, so a test can detect
/// whether the container actually chose (and rendered) the branch it sits in.
/// Each test owns the `Bool`s `mark` flips, so there are no shared fixtures.
private struct ProbeView: View {
    let mark: () -> Void

    var body: some View {
        mark()
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// Reads the runner proxy the container publishes into the environment and
/// reports whether it was connected (i.e. carried a runner) when this view laid
/// out.
private struct EnvironmentRunnerProbe: View {
    @Environment(\.lifecycleRunner) private var runner
    let mark: (Bool) -> Void

    var body: some View {
        mark(runner.base != nil)
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// Drives the run loop up to `timeout` waiting for `condition`, returning
/// whether it ever held. Unlike `waitFor`, a `false` result is a normal
/// outcome — used to assert a branch *never* renders within the budget,
/// without a fixed sleep or hand-rolled run-loop pumping.
@MainActor
private func renders(within timeout: TimeInterval = 0.5, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
    }
    return condition()
}

@MainActor
struct LifecycleContainerTests {
    @Test func readyShowsContent() async throws {
        var content = false
        var splash = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner, splash: { ProbeView { splash = true } }) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
        #expect(!splash)
    }

    @Test func launchingShowsSplash() throws {
        var splash = false
        var content = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in }
        })
        // Not run yet, so the runner is still in .launching.

        let container = LifecycleContainer(runner, splash: { ProbeView { splash = true } }) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { splash }
        }
        #expect(splash)
        #expect(!content)
    }

    @Test func backgroundLaunchShowsNothing() async throws {
        var content = false
        var splash = false
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner, splash: { ProbeView { splash = true } }) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            // Even at .ready, a background launch must not build the app UI:
            // give the host a render budget and confirm neither branch appears.
            #expect(!renders { content || splash })
        }
    }

    @Test func runningShowsActivePresentation() async throws {
        var presentation = false
        var content = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.interactive("gate") { _ in ProbeView { presentation = true } }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("gate") }

        let container = LifecycleContainer(runner) { ProbeView { content = true } }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { presentation }
        }
        #expect(presentation)
        #expect(!content)

        runner.phase.runningBridge?.complete()
        await task.value
    }

    @Test func failedShowsFailureView() async throws {
        var failure = false
        var content = false
        var splash = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("boom") { _ in throw ProbeError() }
        })
        await runner.run()
        #expect(runner.phase.failed(at: "boom"))

        let container = LifecycleContainer(
            runner,
            splash: { ProbeView { splash = true } },
            failure: { _, _ in ProbeView { failure = true } },
        ) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { failure }
        }
        #expect(failure)
        #expect(!content)
        #expect(!splash)
    }

    @Test func publishesTheRunnerIntoTheEnvironment() async throws {
        var sawRunner = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner) {
            EnvironmentRunnerProbe { sawRunner = $0 }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { sawRunner }
        }
        #expect(sawRunner)
    }

    @Test func customTransitionStillRendersContent() async throws {
        // A caller-supplied transition/animation must not break which surface the
        // container renders — at .ready it still builds `content`, not the splash.
        var content = false
        var splash = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            transition: .scale.combined(with: .opacity),
            animation: .easeInOut,
            splash: { ProbeView { splash = true } },
            failure: { _, _ in EmptyView() },
        ) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
        #expect(!splash)
    }

    @Test func defaultRunnerProxyIsDisconnected() {
        // The environment default: nothing to drive, so callers no-op (debug
        // asserts) rather than dereferencing a missing runner.
        #expect(LifecycleRunnerProxy().base == nil)
    }

    @Test func connectedProxyForwardsTeardownToTheRunner() async {
        var tornDown = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        await LifecycleRunnerProxy(runner).teardown(LifecycleSteps {
            LifecycleStep.work("teardown") { _ in tornDown = true }
        })
        #expect(tornDown)
        #expect(runner.phase.isReady)
    }
}
