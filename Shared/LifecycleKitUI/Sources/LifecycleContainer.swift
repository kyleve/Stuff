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

    /// When the splash may be dismissed: the deadline the current appearance's
    /// `minimumSplashDuration` set. `nil` means nothing is holding the reveal —
    /// no minimum was requested, no splash was shown, or the hold has elapsed.
    @State private var splashHoldUntil: ContinuousClock.Instant?

    /// - Parameters:
    ///   - transition: how each surface enters/leaves. Defaults to a crossfade.
    ///   - animation: the animation driving `transition`. Pass `nil` to swap
    ///     surfaces instantly (no animation).
    ///   - minimumSplashDuration: the least time the splash stays up before the
    ///     `.ready` reveal, so a very fast launch still shows the splash (and
    ///     its reveal) rather than flashing past. `.zero` (the default) reveals
    ///     as soon as the runner is ready. The hold isn't dead time: `content`
    ///     is already built beneath the splash, so the destination warms up
    ///     during it rather than in the frame the reveal starts.
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
        // Arm the hold each time the splash appears, so every episode (a reset
        // relaunch, the return from a gate) gets its own minimum.
        .onChange(of: isShowingSplash, initial: true) { _, showing in
            guard showing, minimumSplashDuration > .zero else { return }
            splashHoldUntil = ContinuousClock.now.advanced(by: minimumSplashDuration)
        }
        // Once the runner is ready, wait out whatever is left of the hold, then
        // release the reveal.
        .task(id: runner.phase.isReady) {
            guard runner.phase.isReady, let deadline = splashHoldUntil else { return }
            do {
                // Returns immediately once the deadline has passed, so a launch
                // slower than the minimum reveals without waiting.
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return // Superseded — a new appearance re-armed the hold.
            }
            // Drive the reveal in an explicit transaction: `.animation(_:value:)`
            // doesn't reliably animate this async, `.task`-driven flip, so the
            // splash would be removed without its reveal transition.
            withAnimation(animation) { splashHoldUntil = nil }
        }
    }

    /// Whether the *runner* wants the splash on screen: a launch that builds a
    /// view tree, parked on `.launching` or running a step (step UI lives in
    /// gates, which have their own surface).
    ///
    /// Deliberately reads the runner's own surface, not `displayedSurfaceIdentity`
    /// — that reports `.splash` for a held `.ready`, which would re-arm the hold
    /// from its own release and never reveal.
    private var isShowingSplash: Bool {
        !runner.reason.buildsNoViewTree && runner.phase.surfaceIdentity == .splash
    }

    /// Whether the app content may be revealed: nothing is holding it — no
    /// minimum was requested, no splash was shown, or the hold has elapsed.
    private var canRevealReady: Bool {
        splashHoldUntil == nil
    }

    /// The surface actually on screen, for `.animation(_:value:)`. While the
    /// `.ready` reveal is held behind `minimumSplashDuration` this stays
    /// `.splash`, so the reveal transition fires when the hold releases — not
    /// the instant the runner reports `.ready`.
    private var displayedSurfaceIdentity: LifecycleRunner<Launch>.Phase.SurfaceIdentity {
        if runner.phase.isReady, !canRevealReady {
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

    /// The app content beneath whatever launch surface is up.
    ///
    /// Built as soon as the launch *produces* its value rather than when the
    /// splash hold releases, so the hold warms the destination — its `.task`s,
    /// its first layout — instead of paying for it in the same frame the reveal
    /// animation starts. It's still gated on the launch's own output:
    /// `readyValue` is non-nil only in `.ready`, so `content` can no more be
    /// built without the value than before.
    ///
    /// One `content` call site on purpose: rendering it from two branches
    /// (held vs. revealed) would give SwiftUI two identities and rebuild the
    /// whole destination when the hold releases, which is exactly what
    /// building it early is meant to avoid.
    private var phaseContent: some View {
        ZStack {
            if let value = runner.phase.readyValue {
                content(value)
                    .transition(transition)
                    .zIndex(Self.contentZIndex)
            }
            launchSurface
        }
    }

    /// Which launch surface covers the content right now. Exhaustive over the
    /// phase, so a new case is a compile error here — and every splash-showing
    /// state resolves to the *same* `.splash` case, so the splash keeps one
    /// identity (and its animation/caption timers) from `.launching` through
    /// the steps and the hold, instead of remounting at each boundary.
    private enum LaunchOverlay {
        case splash(LifecycleStepContext?)
        case gate(LifecycleGateHandle)
        case failure(LifecycleFailure)
        /// Nothing covers the content — the reveal has happened.
        case revealed
    }

    private var launchOverlay: LaunchOverlay {
        switch runner.phase {
            case .launching: .splash(nil)
            case let .running(context): .splash(context)
            case let .awaitingGate(handle): .gate(handle)
            case let .failed(failure): .failure(failure)
            // Held behind `minimumSplashDuration`? Keep the splash on top
            // until it elapses; otherwise nothing covers the content.
            case .ready: canRevealReady ? .revealed : .splash(nil)
        }
    }

    @ViewBuilder private var launchSurface: some View {
        switch launchOverlay {
            case let .splash(context):
                splash(context).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .gate(handle):
                gateView(for: handle).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .failure(failure):
                failureView(failure).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case .revealed:
                EmptyView()
        }
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
        minimumSplashDuration: Duration = .zero,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            minimumSplashDuration: minimumSplashDuration,
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
        minimumSplashDuration: Duration = .zero,
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            minimumSplashDuration: minimumSplashDuration,
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
