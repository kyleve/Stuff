import LifecycleKit
@testable import LifecycleKitUI
import SwiftUI
import TestHostSupport
import Testing

private struct ProbeError: LocalizedError {
    var errorDescription: String? {
        "probe failure"
    }
}

/// Reads the proxy the container publishes into the environment and reports
/// whether it was connected (i.e. carried a runner) when this view laid out.
private struct EnvironmentProxyProbe: View {
    @Environment(\.lifecycle) private var lifecycle
    let mark: (Bool) -> Void

    var body: some View {
        mark(lifecycle.base != nil)
        return Color.clear.frame(width: 1, height: 1)
    }
}

@MainActor
struct LifecycleContainerTests {
    private func makeReadyRunner(
        reason: LifecycleReason = .userForeground,
    ) async -> LifecycleRunner<String> {
        let runner = LifecycleRunner(
            reason: reason,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" }),
        )
        await runner.run()
        return runner
    }

    @Test func readyShowsContentBuiltFromTheLaunchValue() async throws {
        var contentValue: String?
        var splash = false
        let runner = await makeReadyRunner()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            splash: { _ in ProbeView { splash = true } },
        ) { value in
            ProbeView { contentValue = value }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { contentValue != nil }
        }
        // The content closure received the trunk's output — not a re-read of
        // shared state.
        #expect(contentValue == "session")
        #expect(!splash)
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
        // splash caption's own delay it's exercised on device, not host-tested.)
        //
        // Asserted via the *splash*, not via `content`: content is built as soon
        // as the runner produces its value — behind the splash while a hold is up,
        // so that the hold warms the destination — so building it no longer
        // distinguishes "revealed" from "held". An absent splash does.
        var content = false
        var splashShown = false
        let runner = await makeReadyRunner()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .seconds(60),
            splash: { _ in ProbeView { splashShown = true } },
            failure: { _ in EmptyView() },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
        // Nothing covering it: the reveal happened rather than stalling behind a
        // 60-second hold for a splash the user never saw.
        #expect(!splashShown)
    }

    @Test func splashBeforeFirstRevealCoversAlreadyReadyContent() async throws {
        var content = false
        var splashShown = false
        let runner = await makeReadyRunner()
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .seconds(60),
            readyRevealPolicy: .splashBeforeFirstReveal,
            splash: { _ in ProbeView { splashShown = true } },
            failure: { _ in EmptyView() },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content && splashShown }
        }

        // Ready content warms beneath the covering splash.
        #expect(content)
        #expect(splashShown)
    }

    @Test func zeroMinimumDoesNotForceAFirstRevealSplash() async throws {
        var content = false
        var splashShown = false
        let runner = await makeReadyRunner()

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .zero,
            readyRevealPolicy: .splashBeforeFirstReveal,
            splash: { _ in ProbeView { splashShown = true } },
            failure: { _ in EmptyView() },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }

        #expect(content)
        #expect(splashShown == false)
    }

    @Test func aCoveringSurfaceHidesTheContentBeneathIt() {
        // `content` is built as soon as the launch produces its value — including
        // while a surface still covers it, so the hold warms it up — which means
        // "covered" has to hold for VoiceOver and touches too, not just visually:
        // an opaque splash doesn't take the content out of the accessibility tree.
        typealias Container = LifecycleContainer<String, EmptyView, EmptyView, EmptyView>
        let context = LifecycleStepContext(stepID: "open", reason: .userForeground)
        let handle = LifecycleGateHandle(id: "onboarding", reason: .userForeground)
        let failure = LifecycleFailure(stepID: "boom", error: ProbeError())

        #expect(Container.overlay(for: .launching, canRevealReady: true).coversContent)
        #expect(Container.overlay(for: .running(context), canRevealReady: true).coversContent)
        #expect(Container.overlay(for: .awaitingGate(handle), canRevealReady: true).coversContent)
        #expect(Container.overlay(for: .failed(failure), canRevealReady: true).coversContent)
        // The case that regressed: ready (so `content` exists) but still held
        // behind `minimumSplashDuration`, with the splash on top of it.
        #expect(Container.overlay(for: .ready("session"), canRevealReady: false).coversContent)
        // Revealed — nothing between the user and the app.
        #expect(!Container.overlay(for: .ready("session"), canRevealReady: true).coversContent)
    }

    @Test func launchingShowsSplash() throws {
        var splash = false
        var content = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" }),
        )
        // Not run yet, so the runner is still in .launching.

        let container = LifecycleContainer(
            runner,
            splash: { _ in ProbeView { splash = true } },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { splash }
        }
        #expect(splash)
        #expect(!content)
    }

    @Test func runningStepContextReachesTheSplash() async throws {
        let (parked, release) = AsyncStream.makeStream(of: Void.self)
        var caption: String?
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, context in
                context.message = "opening the store"
                for await _ in parked {}
                return "session"
            }),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isRunning("open") }

        let container = LifecycleContainer(
            runner,
            splash: { context in ProbeView { caption = context?.message } },
        ) { _ in
            ProbeView {}
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { caption != nil }
        }
        #expect(caption == "opening the store")

        release.finish()
        await task.value
    }

    @Test func splashBeforeFirstRevealKeepsBackgroundReadyHeadless() async throws {
        var content = false
        var splash = false
        let runner = await makeReadyRunner(reason: .background(.location))
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .seconds(60),
            readyRevealPolicy: .splashBeforeFirstReveal,
            splash: { _ in ProbeView { splash = true } },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            // Even at .ready, a background launch must not build the app UI:
            // give the host a render budget and confirm neither branch appears.
            #expect(!renders { content || splash })
        }
    }

    @Test func undeterminedLaunchShowsNothingUntilPromoted() async throws {
        var content = false
        var splash = false
        let runner = await makeReadyRunner(reason: .undetermined)
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            splash: { _ in ProbeView { splash = true } },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            // An undetermined launch hasn't proven a window exists, so — like a
            // background launch — it must build no view tree even at .ready.
            #expect(!renders { content || splash })
        }
    }

    @Test func promotedBackgroundReadyForcesTheFirstRevealSplash() async throws {
        var content = false
        var splash = false
        let runner = await makeReadyRunner(reason: .background(.location))
        #expect(runner.reason.buildsNoViewTree)

        await runner.enterForeground()
        #expect(!runner.reason.buildsNoViewTree)
        #expect(runner.phase.isReady)

        let container = LifecycleContainer(
            runner,
            minimumSplashDuration: .seconds(60),
            readyRevealPolicy: .splashBeforeFirstReveal,
            splash: { _ in ProbeView { splash = true } },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content && splash }
        }
        #expect(content)
        #expect(splash)
    }

    @Test func awaitingGateShowsTheRegisteredGateViewWithTheTrunkValue() async throws {
        var gateValue: String?
        var content = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding")),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }

        let container = LifecycleContainer(
            runner,
            gates: {
                GateView(for: FixtureGate<String>.self) { _, value in
                    ProbeView { gateValue = value }
                }
            },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { gateValue != nil }
        }
        // The registry recovered the gate's Value statically and handed the
        // view the typed trunk value.
        #expect(gateValue == "session")
        #expect(!content)

        runner.phase.gateHandle?.complete()
        await task.value
        #expect(runner.phase.isReady)
    }

    @Test func parkedGateWithNoRegistrationFailsTheGateOntoTheFailureSurface() async throws {
        // A parked gate whose type has no GateView entry is a
        // misconfiguration: the container must fail the handle — landing on
        // the visible (terminal) failure surface (rendering of `.failed` is
        // pinned by `failedShowsFailureView`) — rather than leave the launch
        // behind an indefinite splash that reads as progress.
        var splashShown = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
                .gate(FixtureGate<String>("onboarding")),
        )
        let task = Task { @MainActor in await runner.run() }
        try await waitUntil { runner.phase.isAwaitingGate("onboarding") }

        let container = LifecycleContainer(
            runner,
            splash: { _ in ProbeView { splashShown = true } },
        ) { _ in
            ProbeView {}
        }
        try show(UIHostingController(rootView: container)) { _ in
            // Hosting renders the interim splash and fires the fallback's
            // `onAppear`, which fails the handle. The drive's resumption is a
            // main-actor task continuation, so it can only land after this
            // synchronous block yields — hence the async wait below, not a
            // run-loop-pumping `waitFor` here.
            try waitFor { splashShown }
        }

        try await waitUntil { runner.phase.failed(at: "onboarding") }
        await task.value
        let error = try #require(runner.phase.failure?.error as? MissingGateViewError)
        #expect(error.gateID == AnyHashable("onboarding"))
    }

    @Test func failedShowsFailureView() async throws {
        var failure = false
        var content = false
        var splash = false
        let runner = LifecycleRunner(
            reason: .userForeground,
            plan: LaunchPlan(FixtureStep<Void, String>("boom") { _, _ in throw ProbeError() }),
        )
        await runner.run()
        #expect(runner.phase.failed(at: "boom"))

        let container = LifecycleContainer(
            runner,
            splash: { _ in ProbeView { splash = true } },
            failure: { _ in ProbeView { failure = true } },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { failure }
        }
        #expect(failure)
        #expect(!content)
        #expect(!splash)
    }

    @Test func publishesAConnectedProxyIntoTheEnvironment() async throws {
        var sawRunner = false
        let runner = await makeReadyRunner()

        let container = LifecycleContainer(runner) { _ in
            EnvironmentProxyProbe { sawRunner = $0 }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { sawRunner }
        }
        #expect(sawRunner)
    }

    @Test func customTransitionStillRendersContent() async throws {
        // A caller-supplied transition/animation must not break which surface
        // the container renders — at .ready it still builds `content`.
        var content = false
        var splash = false
        let runner = await makeReadyRunner()

        let container = LifecycleContainer(
            runner,
            transition: .scale.combined(with: .opacity),
            animation: .easeInOut,
            splash: { _ in ProbeView { splash = true } },
            failure: { _ in EmptyView() },
        ) { _ in
            ProbeView { content = true }
        }
        try show(UIHostingController(rootView: container)) { _ in
            try waitFor { content }
        }
        #expect(content)
        #expect(!splash)
    }
}
