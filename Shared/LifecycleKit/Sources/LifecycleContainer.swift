import SwiftUI

extension EnvironmentValues {
    /// A handle to the running `LifecycleRunner`, published by
    /// `LifecycleContainer` so nested views (a custom failure view, a Settings
    /// "reset" button) can reach `retry()`/`teardown()` without prop-drilling.
    ///
    /// It's a `LifecycleRunnerProxy` rather than a bare `LifecycleRunner?` so a
    /// view that reads it can just *call* the runner: when no container is above
    /// (previews, isolated tests) the proxy is disconnected and every call
    /// asserts in debug — surfacing the missing container — and no-ops in
    /// release, instead of each call site silently `guard`ing the optional away.
    @Entry public var lifecycleRunner = LifecycleRunnerProxy()
}

/// A debug-loud, release-quiet handle to the environment's `LifecycleRunner`.
///
/// `LifecycleContainer` publishes a *connected* proxy; the environment default
/// is *disconnected* (no runner). Calling through a disconnected proxy
/// `assertionFailure`s in debug (so a view used outside a container is caught in
/// development) and no-ops in release (so a stray reset/retry tap can't crash a
/// shipping build). Views therefore drive the runner without `guard`ing — the
/// "is there a runner?" decision lives here, once.
///
/// The wrapped `LifecycleRunner` is `@MainActor`; every forwarding entry point
/// is annotated `@MainActor` accordingly. The struct itself stays `Sendable` so
/// it can be the `@Entry` default — callers must invoke it from the main actor
/// (SwiftUI views already do).
public struct LifecycleRunnerProxy: Sendable {
    let base: LifecycleRunner?

    /// A disconnected proxy (no runner): the environment default, and what
    /// previews get so reset/retry quietly do nothing.
    public init() {
        base = nil
    }

    init(_ runner: LifecycleRunner) {
        base = runner
    }

    /// Resume a failed launch from the step that failed.
    /// See `LifecycleRunner.retry()`.
    @MainActor public func retry(file: StaticString = #fileID, line: UInt = #line) {
        connected(file: file, line: line)?.retry()
    }

    /// Run a teardown `sequence`, then relaunch from the top.
    /// See `LifecycleRunner.teardown(_:)`.
    @MainActor public func teardown(
        _ sequence: LifecycleSteps,
        file: StaticString = #fileID,
        line: UInt = #line,
    ) async {
        await connected(file: file, line: line)?.teardown(sequence)
    }

    /// Promote a headless background launch to the foreground.
    /// See `LifecycleRunner.enterForeground()`.
    @MainActor public func enterForeground(file: StaticString = #fileID, line: UInt = #line) async {
        await connected(file: file, line: line)?.enterForeground()
    }

    /// The wrapped runner, or nil with a debug assertion pointing at the caller —
    /// so a disconnected proxy is loud in development and a silent no-op in
    /// production.
    private func connected(file: StaticString, line: UInt) -> LifecycleRunner? {
        if base == nil {
            assertionFailure(
                "No LifecycleRunner in the environment — is this view inside a LifecycleContainer?",
                file: file,
                line: line,
            )
        }
        return base
    }
}

/// The root view that renders a `LifecycleRunner`'s `phase`.
///
/// The launch sequence is only the *prerequisites*; the destination — the
/// app's real, "logged-in" UI — is the `content` closure, shown when the
/// runner reaches `.ready`. Pass an already-built runner (created early,
/// e.g. in the app delegate, so a headless background launch works without a
/// window).
///
/// The `splash` and `failure` views are caller-injectable; convenience
/// initializers default them to the built-in `LifecycleSplash` /
/// `LifecycleFailureView`. The runner is published into the environment
/// (`\.lifecycleRunner`) for nested views to reach.
///
/// Surface changes (splash → failure → app `content`) are animated with the
/// caller-supplied `transition`/`animation` (a crossfade by default), keyed on
/// `LifecyclePhase.surfaceIdentity` so a step *advancing* — which keeps showing
/// the splash — doesn't retrigger the transition and flash it.
///
/// For a background launch, the container renders nothing at all (iOS never
/// shows UI for a headless relaunch and reclaims memory aggressively), so
/// `content` is never constructed even once the runner reaches `.ready`.
public struct LifecycleContainer<Content: View, Splash: View, Failure: View>: View {
    private let runner: LifecycleRunner
    private let transition: AnyTransition
    private let animation: Animation?
    private let splash: () -> Splash
    private let failureView: (LifecycleFailure, @escaping () -> Void) -> Failure
    private let content: () -> Content

    /// - Parameters:
    ///   - transition: how each surface enters/leaves. Defaults to a crossfade.
    ///   - animation: the animation driving `transition`. Pass `nil` to swap
    ///     surfaces instantly (no animation).
    public init(
        _ runner: LifecycleRunner,
        transition: AnyTransition = .opacity,
        animation: Animation? = .default,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure, @escaping () -> Void) -> Failure,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.runner = runner
        self.transition = transition
        self.animation = animation
        self.splash = splash
        failureView = failure
        self.content = content
    }

    public var body: some View {
        Group {
            if runner.reason.isBackground {
                EmptyView()
            } else {
                phaseContent
            }
        }
        .environment(\.lifecycleRunner, LifecycleRunnerProxy(runner))
        .animation(animation, value: runner.phase.surfaceIdentity)
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
            case .launching:
                splash().transition(transition)
            case let .running(_, bridge):
                // Show the step's active presentation if it has one, otherwise
                // fall back to the splash. Reading `bridge.presentation` makes
                // a deferred (`presenting(after:)`) presentation appear without
                // a phase change.
                if let presentation = bridge.presentation {
                    presentation.transition(transition)
                } else {
                    splash().transition(transition)
                }
            case let .failed(failure):
                failureView(failure) { runner.retry() }.transition(transition)
            case .ready:
                content().transition(transition)
        }
    }
}

extension LifecycleContainer where Splash == LifecycleSplash, Failure == LifecycleFailureView {
    /// Convenience initializer using the built-in splash and failure views.
    public init(
        _ runner: LifecycleRunner,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(
            runner,
            splash: { LifecycleSplash() },
            failure: { LifecycleFailureView(failure: $0, retry: $1) },
            content: content,
        )
    }
}

extension LifecycleContainer where Failure == LifecycleFailureView {
    /// Convenience initializer with a custom splash but the built-in failure
    /// view.
    public init(
        _ runner: LifecycleRunner,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(
            runner,
            splash: splash,
            failure: { LifecycleFailureView(failure: $0, retry: $1) },
            content: content,
        )
    }
}

#if DEBUG
    #Preview("Launching") {
        LifecycleContainer(
            LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
                LifecycleStep.work("open") { _ in }
            }),
        ) {
            Text("App content")
        }
    }
#endif
