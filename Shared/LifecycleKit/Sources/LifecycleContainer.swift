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
/// the splash — doesn't retrigger the transition and flash it. The launch
/// surfaces are layered above `content`, so a *leaving* splash plays its
/// removal transition over the *entering* destination (a scale-up-and-fade
/// reveal, say) instead of being clipped to a pop behind it.
///
/// For a launch that builds no view tree (`.background`, or an `.undetermined`
/// one not yet promoted), the container renders nothing at all (iOS never shows
/// UI for a headless relaunch and reclaims memory aggressively), so `content`
/// is never constructed even once the runner reaches `.ready`.
public struct LifecycleContainer<Content: View, Splash: View, Failure: View>: View {
    private let runner: LifecycleRunner
    private let transition: AnyTransition
    private let animation: Animation?
    private let minimumSplashDuration: Duration
    private let splash: () -> Splash
    private let failureView: (LifecycleFailure, @escaping () -> Void) -> Failure
    private let content: () -> Content

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
    public init(
        _ runner: LifecycleRunner,
        transition: AnyTransition = .opacity,
        animation: Animation? = .default,
        minimumSplashDuration: Duration = .zero,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure, @escaping () -> Void) -> Failure,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.runner = runner
        self.transition = transition
        self.animation = animation
        self.minimumSplashDuration = minimumSplashDuration
        self.splash = splash
        failureView = failure
        self.content = content
    }

    public var body: some View {
        Group {
            if runner.reason.buildsNoViewTree {
                EmptyView()
            } else {
                phaseContent
            }
        }
        .environment(\.lifecycleRunner, LifecycleRunnerProxy(runner))
        .animation(animation, value: displayedSurfaceIdentity)
        // Record when the splash first shows so the reveal can be held for at
        // least `minimumSplashDuration`. Resets each time the splash reappears
        // (a reset relaunch, or the return from onboarding) so every episode
        // gets its own minimum.
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

    /// Whether the splash is actually on screen right now: a launch that builds a
    /// view tree, parked on `.launching` or a `.running` step not showing its own
    /// presentation.
    private var isShowingSplash: Bool {
        guard !runner.reason.buildsNoViewTree else { return false }
        switch runner.phase {
            case .launching: return true
            case let .running(_, bridge): return bridge.presentation == nil
            case .failed, .ready: return false
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
    /// `.splash`, so the reveal transition fires when the hold releases — not the
    /// instant the runner reports `.ready`.
    private var displayedSurfaceIdentity: LifecyclePhase.SurfaceIdentity {
        if isReadyPhase, !canRevealReady {
            return .splash
        }
        return runner.phase.surfaceIdentity
    }

    /// Launch surfaces (splash / step presentation / failure) sit above the
    /// app `content` so that when the runner reaches `.ready`, a *leaving* splash
    /// animates on top of the *entering* content — letting a removal transition
    /// (e.g. the Where launch splash scaling up and fading to reveal the UI) play
    /// over the destination instead of being hidden behind freshly-inserted
    /// content. With equal z-indices SwiftUI draws the inserted view last, which
    /// would clip the reveal to a plain pop.
    private static var launchSurfaceZIndex: Double {
        1
    }

    private static var contentZIndex: Double {
        0
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
            case .launching:
                splashSurface
            case let .running(_, bridge):
                // Show the step's active presentation if it has one, otherwise
                // fall back to the splash. Reading `bridge.presentation` makes
                // a deferred (`presenting(after:)`) presentation appear without
                // a phase change.
                if let presentation = bridge.presentation {
                    presentation.transition(transition).zIndex(Self.launchSurfaceZIndex)
                } else {
                    splashSurface
                }
            case let .failed(failure):
                failureView(failure) { runner.retry() }
                    .transition(transition)
                    .zIndex(Self.launchSurfaceZIndex)
            case .ready:
                // Keep the splash up until its minimum has elapsed (see
                // `minimumSplashDuration`), then reveal the app content.
                if canRevealReady {
                    content().transition(transition).zIndex(Self.contentZIndex)
                } else {
                    splashSurface
                }
        }
    }

    private var splashSurface: some View {
        splash().transition(transition).zIndex(Self.launchSurfaceZIndex)
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
