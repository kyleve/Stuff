@testable import LifecycleKit
import SwiftUI
import TestHostSupport
import Testing

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

    @Test func backgroundReadyThenEnterForegroundShowsContent() async throws {
        var content = false
        let runner = LifecycleRunner(reason: .background(.location), sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
    }

    @Test func undeterminedLaunchShowsNothingUntilPromoted() async throws {
        var content = false
        var splash = false
        let runner = LifecycleRunner(reason: .undetermined, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner, splash: { ProbeView { splash = true } }) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            // An undetermined launch hasn't proven a window exists, so — like a
            // background launch — it must build no view tree even at .ready.
            #expect(!renders { content || splash })
        }
    }

    @Test func undeterminedReadyThenEnterForegroundShowsContent() async throws {
        var content = false
        let runner = LifecycleRunner(reason: .undetermined, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(runner) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
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

    @Test func minimumSplashDurationDoesNotHoldWhenNoSplashWasShown() async throws {
        // The minimum only holds a splash that actually appeared. A launch that's
        // already ready when the container mounts never showed one, so even a long
        // minimum must reveal content immediately rather than stalling on a hold
        // for a splash the user never saw.
        //
        // (The other half — holding a splash that *did* appear until the minimum
        // elapses, then revealing — is a `.task`-driven async/timing behavior that
        // `show`'s synchronous closure can't drive deterministically; like the
        // splash caption's own delay it's exercised on device, not host-tested.
        // See `LaunchSplashView.previewShowsCaption`.)
        var content = false
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {})
        await runner.run()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .seconds(60),
            splash: { EmptyView() },
            failure: { _, _ in EmptyView() },
        ) {
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
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
