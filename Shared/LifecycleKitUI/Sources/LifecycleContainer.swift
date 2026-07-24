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
    private let splash: (LifecycleStepContext?) -> Splash
    private let failureView: (LifecycleFailure) -> Failure
    private let gates: [GateRegistration]
    private let content: (Launch) -> Content

    /// - Parameters:
    ///   - transition: how each surface enters/leaves. Defaults to a crossfade.
    ///   - animation: the animation driving `transition`. Pass `nil` to swap
    ///     surfaces instantly (no animation).
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
        @ViewBuilder splash: @escaping (LifecycleStepContext?) -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure) -> Failure,
        @GateRegistrationsBuilder gates: () -> [GateRegistration] = { [] },
        @ViewBuilder content: @escaping (Launch) -> Content,
    ) {
        self.runner = runner
        self.transition = transition
        self.animation = animation
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
        .animation(animation, value: runner.phase.surfaceIdentity)
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
                splash(nil).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .running(context):
                splash(context).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .awaitingGate(handle):
                gateView(for: handle).transition(transition).zIndex(Self.launchSurfaceZIndex)
            case let .failed(failure):
                failureView(failure)
                    .transition(transition)
                    .zIndex(Self.launchSurfaceZIndex)
            case let .ready(value):
                content(value).transition(transition).zIndex(Self.contentZIndex)
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
