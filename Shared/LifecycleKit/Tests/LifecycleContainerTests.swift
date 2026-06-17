import LifecycleKit
import SwiftUI
import Testing
import WhereTesting

private struct ProbeError: LocalizedError {
    var errorDescription: String? {
        "probe failure"
    }
}

/// Records whether each branch of `LifecycleContainer` actually built its view,
/// detected by a side effect in `ProbeView.body` (which only runs when the
/// container chooses that branch and the host lays it out).
@MainActor
private final class RenderFlags {
    var splash = false
    var content = false
    var presentation = false
    var failure = false
}

private struct ProbeView: View {
    let mark: () -> Void

    var body: some View {
        mark()
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// Reads the runner the container publishes into the environment and reports
/// whether it was present when this view laid out.
private struct EnvironmentRunnerProbe: View {
    @Environment(\.lifecycleRunner) private var runner
    let mark: (Bool) -> Void

    var body: some View {
        mark(runner != nil)
        return Color.clear.frame(width: 1, height: 1)
    }
}

@MainActor
private func makeContainer(
    _ runner: LifecycleRunner,
    flags: RenderFlags,
) -> some View {
    LifecycleContainer(
        runner,
        splash: { ProbeView { flags.splash = true } },
        failure: { _, _ in ProbeView { flags.failure = true } },
    ) {
        ProbeView { flags.content = true }
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
        let flags = RenderFlags()
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        try show(UIHostingController(rootView: makeContainer(runner, flags: flags))) { _ in
            try waitFor { flags.content }
        }
        #expect(flags.content)
        #expect(!flags.splash)
    }

    @Test func launchingShowsSplash() throws {
        let flags = RenderFlags()
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("a") { _ in }
        })
        // Not run yet, so the runner is still in .launching.

        try show(UIHostingController(rootView: makeContainer(runner, flags: flags))) { _ in
            try waitFor { flags.splash }
        }
        #expect(flags.splash)
        #expect(!flags.content)
    }

    @Test func backgroundLaunchShowsNothing() async throws {
        let flags = RenderFlags()
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        try show(UIHostingController(rootView: makeContainer(runner, flags: flags))) { _ in
            // Even at .ready, a background launch must not build the app UI:
            // give the host a render budget and confirm neither branch appears.
            #expect(!renders { flags.content || flags.splash })
        }
    }

    @Test func runningShowsActivePresentation() async throws {
        let flags = RenderFlags()
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.interactive("gate") { _ in ProbeView { flags.presentation = true } }
        })
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.runningStepID == "gate" }

        try show(UIHostingController(rootView: makeContainer(runner, flags: flags))) { _ in
            try waitFor { flags.presentation }
        }
        #expect(flags.presentation)
        #expect(!flags.content)

        runner.phase.runningBridge?.complete()
        await task.value
    }

    @Test func failedShowsFailureView() async throws {
        let flags = RenderFlags()
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("boom") { _ in throw ProbeError() }
        })
        await runner.run()
        #expect(runner.phase.failure?.stepID == "boom")

        try show(UIHostingController(rootView: makeContainer(runner, flags: flags))) { _ in
            try waitFor { flags.failure }
        }
        #expect(flags.failure)
        #expect(!flags.content)
        #expect(!flags.splash)
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
}
