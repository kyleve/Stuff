import LifecycleKit
import os
import SwiftUI

/// The root view that renders a `LifecycleRunner`'s `phase`.
///
/// The launch plan is only the *prerequisites*; the destination — the app's
/// real, "logged-in" UI — is the `content` closure, shown when the runner
/// reaches `.ready` and handed the trunk's output (`Launch`), so the app
/// surface literally cannot be built without the value the launch produced.
/// Pass an already-built runner (created early, e.g. in the app delegate, so
/// a headless background launch works without a window).
///
/// The `splash` and `failure` views are caller-injectable; convenience
/// initializers default them to the built-in `LifecycleSplash` /
/// `LifecycleFailureView`. Gate views are registered by gate *type* via
/// `GateView(for:content:)` — the engine's gates carry no views, and the
/// registry recovers each gate's `Value` statically, so the gate view
/// receives `(handle, value)` rather than trusting shared state. A proxy for
/// the runner is published into the environment (`\.lifecycle`) for nested
/// views to reach `enterForeground()`/`teardown(_:input:)`. A failed launch
/// is terminal — the failure surface offers no retry.
///
/// Surface changes (splash → gate → failure → app `content`) are animated
/// with the caller-supplied `transition`/`animation` (a crossfade by
/// default), keyed on the phase's surface identity so a step *advancing* —
/// which keeps showing the splash — doesn't retrigger the transition and
/// flash it. The launch surfaces are layered above `content`, so a *leaving*
/// surface plays its removal transition over the *entering* destination (a
/// scale-up-and-fade reveal, say) instead of being clipped to a pop behind
/// it.
///
/// For a launch that builds no view tree (`.background`, or an
/// `.undetermined` one not yet promoted), the container renders nothing at
/// all (iOS never shows UI for a headless relaunch and reclaims memory
/// aggressively), so `content` is never constructed even once the runner
/// reaches `.ready`.
public struct LifecycleContainer<
    Launch: Sendable,
    Content: View,
    Splash: View,
    Failure: View,
>: View {
    private let runner: LifecycleRunner<Launch>
    private let transition: AnyTransition
    private let animation: Animation?
    private let minimumSplashDuration: Duration
    private let splash: (LifecycleStepContext?) -> Splash
    private let failureView: (LifecycleFailure) -> Failure
    private let gates: [GateRegistration]
    private let content: (Launch) -> Content

    /// When the splash surface first became visible this launch, and whether
    /// `minimumSplashDuration` has since elapsed. Together they gate holding the
    /// `.ready` reveal until the splash has shown for its minimum.
    @State private var splashAppearedAt: ContinuousClock.Instant?
    @State private var minimumSplashElapsed = false

    /// - Parameters:
    ///   - transition: how each surface enters/leaves. Defaults to a crossfade.
    ///   - animation: the animation driving `transition`. Pass `nil` to swap
    ///     surfaces instantly (no animation).
    ///   - minimumSplashDuration: the least time the splash stays up before the
    ///     `.ready` reveal, so a very fast launch still shows the splash (and
    ///     its reveal) rather than flashing past. `.zero` (the default) reveals
    ///     as soon as the runner is ready.
    ///   - splash: the waiting surface; receives the running step's context
    ///     (nil between steps) so it can show a caption/progress.
    ///   - failure: the (terminal) error surface, given the failure. There is
    ///     no retry — the recovery for a failed launch is relaunching the app.
    ///   - gates: the gate-type → view registrations (`GateView(for:content:)`).
    ///   - content: the app's destination UI, given the launch's output.
    public init(
        _ runner: LifecycleRunner<Launch>,
        transition: AnyTransition = .opacity,
        animation: Animation? = .default,
        minimumSplashDuration: Duration = .zero,
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure) -> Failure,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.runner = runner
        self.transition = transition
        self.animation = animation
        self.minimumSplashDuration = minimumSplashDuration
        self.splash = splash
        failureView = failure
        self.gates = gates()
        self.content = content
        Self.assertUniqueGateTypes(self.gates)
    }

    /// One registration per gate type: the parked handle is matched by type,
    /// so a duplicate would make the lookup ambiguous. A duplicate is a
    /// programmer error — fail fast at construction.
    private static func assertUniqueGateTypes(_ gates: [GateRegistration]) {
        var seen = Set<ObjectIdentifier>()
        let duplicates = gates.map(\.gateType).filter { !seen.insert($0).inserted }
        precondition(
            duplicates.isEmpty,
            "LifecycleContainer registered the same gate type more than once.",
        )
    }

    public var body: some View {
        Group {
            if runner.reason.buildsNoViewTree {
                EmptyView()
            } else {
                phaseContent
            }
        }
        .environment(\.lifecycle, LifecycleProxy(runner))
        .animation(animation, value: displayedSurfaceIdentity)
        // Record when the splash first shows so the reveal can be held for at
        // least `minimumSplashDuration`. Resets each time the splash reappears
        // (a reset relaunch, or the return from a gate) so every episode gets
        // its own minimum.
        .onChange(of: isShowingSplash, initial: true) { _, showing in
            guard showing else { return }
            splashAppearedAt = ContinuousClock.now
            minimumSplashElapsed = false
        }
        // Once the runner is ready, hold the splash for the remainder of its
        // minimum (if any), then release the reveal.
        .task(id: isReadyPhase) {
            guard isReadyPhase,
                  minimumSplashDuration > .zero,
                  !minimumSplashElapsed,
                  let appearedAt = splashAppearedAt
            else { return }
            let remaining = minimumSplashDuration - appearedAt.duration(to: ContinuousClock.now)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled else { return }
            }
            // Drive the reveal in an explicit transaction: `.animation(_:value:)`
            // doesn't reliably animate this async, `.task`-driven flip, so the
            // splash would be removed without its reveal transition.
            withAnimation(animation) { minimumSplashElapsed = true }
        }
    }

    /// Whether the splash is actually on screen right now: a launch that builds
    /// a view tree, parked on `.launching` or running a step (which always shows
    /// the splash — step UI lives in gates, which have their own surface).
    private var isShowingSplash: Bool {
        guard !runner.reason.buildsNoViewTree else { return false }
        switch runner.phase {
            case .launching, .running: return true
            case .awaitingGate, .failed, .ready: return false
        }
    }

    private var isReadyPhase: Bool {
        if case .ready = runner.phase { return true }
        return false
    }

    /// Whether the app content may be revealed: no minimum was requested, no
    /// splash was ever shown, or the minimum has now elapsed.
    private var canRevealReady: Bool {
        minimumSplashDuration <= .zero || splashAppearedAt == nil || minimumSplashElapsed
    }

    /// The surface actually on screen, for `.animation(_:value:)`. While the
    /// `.ready` reveal is held behind `minimumSplashDuration` this stays
    /// `.splash`, so the reveal transition fires when the hold releases — not
    /// the instant the runner reports `.ready`.
    private var displayedSurfaceIdentity: LifecycleRunner<Launch>.Phase.SurfaceIdentity {
        if isReadyPhase, !canRevealReady {
            return .splash
        }
        return runner.phase.surfaceIdentity
    }

    /// Launch surfaces (splash / gate view / failure) sit above the app
    /// `content` so that when the runner reaches `.ready`, a *leaving* surface
    /// animates on top of the *entering* content — letting a removal
    /// transition (e.g. the Where launch splash scaling up and fading to
    /// reveal the UI) play over the destination instead of being hidden
    /// behind freshly-inserted content. With equal z-indices SwiftUI draws
    /// the inserted view last, which would clip the reveal to a plain pop.
    private static var launchSurfaceZIndex: Double {
        1
    }

    private static var contentZIndex: Double {
        0
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
            case .launching:
                splashSurface(nil)
            case let .running(context):
                splashSurface(context)
            case let .awaitingGate(handle):
                gateView(for: handle).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .failed(failure):
                failureView(failure)
                    .transition(transition)
                    .zIndex(Self.launchSurfaceZIndex)
            case let .ready(value):
                // Keep the splash up until its minimum has elapsed (see
                // `minimumSplashDuration`), then reveal the app content.
                if canRevealReady {
                    content(value).transition(transition).zIndex(Self.contentZIndex)
                } else {
                    splashSurface(nil)
                }
        }
    }

    private func splashSurface(_ context: LifecycleStepContext?) -> some View {
        splash(context).transition(transition).zIndex(Self.launchSurfaceZIndex)
    }

    /// The registered view for the parked gate. A parked gate with no
    /// registration is a programmer error (the plan gates on something the
    /// UI can't render); rather than an indefinite splash that reads as
    /// progress, log it and fail the gate's handle so the launch lands on
    /// the failure surface — visible and named (though terminal). Identical
    /// in debug and release, which also keeps the path testable.
    ///
    /// The handle is failed from `onAppear`, not during `body`: `fail(_:)`
    /// only resumes the drive's parked continuation, so the phase change it
    /// causes lands on the drive task after this render commits. The splash
    /// shows for the beat in between.
    @ViewBuilder
    private func gateView(for handle: LifecycleGateHandle) -> some View {
        if let gateType = handle.gateType,
           let value = handle.value,
           let registration = gates.first(where: { $0.gateType == gateType })
        {
            registration.build(handle, value)
        } else {
            splash(nil).onAppear {
                Self.logger.error(
                    "No gate view registered for gate '\(String(describing: handle.id), privacy: .public)' — add a GateView(for:) entry.",
                )
                handle.fail(MissingGateViewError(gateID: handle.id))
            }
        }
    }

    /// LifecycleKitUI deliberately has no app logging facade; the one
    /// misconfiguration it can detect logs through `os` directly so the
    /// signal isn't state-only.
    private static var logger: Logger {
        Logger(subsystem: "com.stuff.lifecyclekitui", category: "gates")
    }
}

extension LifecycleContainer where Splash == LifecycleSplash, Failure == LifecycleFailureView {
    /// Convenience initializer using the built-in splash and failure views.
    public init(
        _ runner: LifecycleRunner<Launch>,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            splash: { _ in LifecycleSplash() },
            failure: { LifecycleFailureView(failure: $0) },
            gates: gates,
            content: content,
        )
    }
}

extension LifecycleContainer where Failure == LifecycleFailureView {
    /// Convenience initializer with a custom splash but the built-in failure
    /// view.
    public init(
        _ runner: LifecycleRunner<Launch>,
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            splash: splash,
            failure: { LifecycleFailureView(failure: $0) },
            gates: gates,
            content: content,
        )
    }
}

#if DEBUG
    private struct PreviewStep: LifecycleStep {
        let id: AnyHashable = "open"

        func run(_: Void, _: LifecycleStepContext) async throws -> String {
            "session"
        }
    }

    #Preview("Launching") {
        LifecycleContainer(
            LifecycleRunner(reason: .userForeground, plan: LaunchPlan(PreviewStep())),
        ) { value in
            Text(verbatim: "App content for \(value)")
        }
    }
#endif
