import SwiftUI

extension EnvironmentValues {
    /// The running `LifecycleRunner`, published by `LifecycleContainer` so
    /// nested views (a custom failure view, a Settings "reset" button) can
    /// reach `retry()`/`teardown()` without prop-drilling. Nil when no container
    /// is above — previews and isolated tests — so reads stay safe.
    @Entry public var lifecycleRunner: LifecycleRunner?
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
/// For a background launch, the container renders nothing at all (iOS never
/// shows UI for a headless relaunch and reclaims memory aggressively), so
/// `content` is never constructed even once the runner reaches `.ready`.
public struct LifecycleContainer<Content: View, Splash: View, Failure: View>: View {
    private let runner: LifecycleRunner
    private let splash: () -> Splash
    private let failureView: (LifecycleFailure, @escaping () -> Void) -> Failure
    private let content: () -> Content

    public init(
        _ runner: LifecycleRunner,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder failure: @escaping (LifecycleFailure, @escaping () -> Void) -> Failure,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.runner = runner
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
        .environment(\.lifecycleRunner, runner)
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
            case .launching:
                splash()
            case let .running(_, bridge):
                // Show the step's active presentation if it has one, otherwise
                // fall back to the splash. Reading `bridge.presentation` makes
                // a deferred (`presenting(after:)`) presentation appear without
                // a phase change.
                if let presentation = bridge.presentation {
                    presentation
                } else {
                    splash()
                }
            case let .failed(failure):
                failureView(failure) { runner.retry() }
            case .ready:
                content()
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
