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
    private let isPresentationVisible: Bool
    private let splash: (LifecycleStepContext?) -> Splash
    private let failureView: (LifecycleFailure) -> Failure
    private let gates: [GateRegistration]
    private let content: (Launch) -> Content

    /// One value tracks whether the first visible ready presentation still
    /// owes the user a splash, a rendered splash is being held, or content has
    /// already been revealed. Kept scene-local by SwiftUI's state lifetime.
    @State private var readyRevealState: LifecycleReadyRevealState

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
    ///   - isPresentationVisible: whether the containing scene is active. Apps
    ///     with a positive minimum should pass their active-scene state so an
    ///     interrupted hold cannot complete offscreen.
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
        isPresentationVisible: Bool = true,
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure) -> Failure,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.runner = runner
        self.transition = transition
        self.animation = animation
        self.minimumSplashDuration = minimumSplashDuration
        self.isPresentationVisible = isPresentationVisible
        self.splash = splash
        failureView = failure
        self.gates = gates()
        self.content = content
        _readyRevealState = State(
            initialValue: LifecycleReadyRevealState(
                minimumSplashDuration: minimumSplashDuration,
            ),
        )
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
            guard showing else { return }
            readyRevealState.splashAppeared(
                at: .now,
                minimumSplashDuration: minimumSplashDuration,
            )
        }
        // A promoted runner's reason stays foreground forever, so scene activity
        // is the separate authority on whether this presentation is actually
        // visible. If the user leaves before content is revealed, do not let the
        // first-reveal obligation expire offscreen.
        .onChange(of: isPresentationVisible, initial: true) { _, active in
            guard active == false else { return }
            readyRevealState.sceneBecameInactive()
        }
        // Include visibility in the identity: a background runner can remain
        // `.ready` across foreground promotion, and that false → true transition
        // is what must start the first-reveal hold.
        .task(id: isReadyAndVisible) {
            guard isReadyAndVisible else { return }
            readyRevealState.readyBecameVisible(
                at: .now,
                minimumSplashDuration: minimumSplashDuration,
            )
            guard let deadline = readyRevealState.splashHoldDeadline else { return }
            do {
                // Returns immediately once the deadline has passed, so a launch
                // slower than the minimum reveals without waiting.
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return // Superseded — a new appearance re-armed the hold.
            }
            guard
                Task.isCancelled == false,
                isReadyAndVisible,
                readyRevealState.splashHoldDeadline == deadline
            else { return }
            // Drive the reveal in an explicit transaction: `.animation(_:value:)`
            // doesn't reliably animate this async, `.task`-driven flip, so the
            // splash would be removed without its reveal transition.
            withAnimation(animation) { readyRevealState.splashHoldElapsed() }
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
        isPresentationVisible
            && !runner.reason.buildsNoViewTree
            && runner.phase.surfaceIdentity == .splash
    }

    /// Ready and eligible to render a tree. Unlike readiness alone, this flips
    /// when a headless-ready runner is promoted without publishing a different
    /// terminal phase.
    private var isReadyAndVisible: Bool {
        isPresentationVisible && runner.phase.isReady && !runner.reason.buildsNoViewTree
    }

    /// Whether presentation history permits the ready content to show: the
    /// positive minimum owes no first splash and no rendered-splash hold remains.
    private var canRevealReady: Bool {
        readyRevealState.canRevealReady
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
    ///
    /// Because it's in the tree early, it's explicitly hidden from VoiceOver
    /// and hit-testing while a surface covers it — an opaque splash hides it
    /// visually, but not from assistive technology.
    private var phaseContent: some View {
        let overlay = launchOverlay
        return ZStack {
            if let value = runner.phase.readyValue {
                content(value)
                    // Warmed up beneath the launch surface, but not *reachable*
                    // through it. An opaque splash hides the content visually;
                    // without these it stays in the accessibility tree and the
                    // hit-test path, so during the hold VoiceOver could focus an
                    // app the user can't see yet.
                    .accessibilityHidden(overlay.coversContent)
                    .allowsHitTesting(!overlay.coversContent)
                    .transition(transition)
                    .zIndex(Self.contentZIndex)
            }
            launchSurface(overlay)
        }
    }

    /// Which launch surface covers the content right now. Exhaustive over the
    /// phase, so a new case is a compile error here — and every splash-showing
    /// state resolves to the *same* `.splash` case, so the splash keeps one
    /// identity (and its animation/caption timers) from `.launching` through
    /// the steps and the hold, instead of remounting at each boundary.
    enum LaunchOverlay {
        case splash(LifecycleStepContext?)
        case gate(LifecycleGateHandle)
        case failure(LifecycleFailure)
        /// Nothing covers the content — the reveal has happened.
        case revealed

        /// Whether this surface stands between the user and `content`. Drives
        /// the content's accessibility/hit-testing so "covered" means covered
        /// for every input method, not just visually.
        var coversContent: Bool {
            switch self {
                case .splash, .gate, .failure: true
                case .revealed: false
            }
        }
    }

    private var launchOverlay: LaunchOverlay {
        Self.overlay(for: runner.phase, canRevealReady: canRevealReady)
    }

    /// Pure so the surface decision — including the held-`.ready` case, which
    /// depends on view `@State` and can't be reached from a test otherwise —
    /// is checkable without hosting the container.
    static func overlay(
        for phase: LifecycleRunner<Launch>.Phase,
        canRevealReady: Bool,
    ) -> LaunchOverlay {
        switch phase {
            case .launching: .splash(nil)
            case let .running(context): .splash(context)
            case let .awaitingGate(handle): .gate(handle)
            case let .failed(failure): .failure(failure)
            // Held behind `minimumSplashDuration`? Keep the splash on top
            // until it elapses; otherwise nothing covers the content.
            case .ready: canRevealReady ? .revealed : .splash(nil)
        }
    }

    @ViewBuilder private func launchSurface(_ overlay: LaunchOverlay) -> some View {
        switch overlay {
            case let .splash(context):
                splash(context).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .gate(handle):
                gateView(for: handle).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .failure(failure):
                failureView(failure).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case .revealed:
                // Timer expiry only permits the overlay to leave. Make the
                // reveal sticky after SwiftUI commits that uncovered frame, so
                // an intervening inactive scene still owes its first reveal.
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .onAppear {
                        guard isPresentationVisible, runner.phase.isReady else { return }
                        readyRevealState.contentDidReveal()
                    }
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
        isPresentationVisible: Bool = true,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            minimumSplashDuration: minimumSplashDuration,
            isPresentationVisible: isPresentationVisible,
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
        isPresentationVisible: Bool = true,
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.init(
            runner,
            minimumSplashDuration: minimumSplashDuration,
            isPresentationVisible: isPresentationVisible,
            splash: splash,
            failure: { LifecycleFailureView(failure: $0) },
            gates: gates,
            content: content,
        )
    }
}

#if DEBUG
    private struct PreviewStep: LifecycleStep {
        let id = "open"

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
