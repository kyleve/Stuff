import SwiftUI

/// The root view that renders a `LifecycleRunner`'s `phase`.
///
/// The launch sequence is only the *prerequisites*; the destination — the
/// app's real, "logged-in" UI — is the `content` closure, shown when the
/// runner reaches `.ready`. Pass an already-built runner (created early,
/// e.g. in the app delegate, so a headless background launch works without a
/// window).
///
/// For a background launch, the container renders nothing at all (iOS never
/// shows UI for a headless relaunch and reclaims memory aggressively), so
/// `content` is never constructed even once the runner reaches `.ready`.
public struct LifecycleContainer<Content: View, Splash: View>: View {
    private let runner: LifecycleRunner
    private let splash: () -> Splash
    private let content: () -> Content

    public init(
        _ runner: LifecycleRunner,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.runner = runner
        self.splash = splash
        self.content = content
    }

    public var body: some View {
        if runner.reason.isBackground {
            EmptyView()
        } else {
            phaseContent
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
            case .launching:
                splash()
            case let .running(_, bridge):
                LifecycleRunningView(bridge: bridge, splash: splash)
            case let .failed(failure):
                LifecycleFailureView(failure: failure) { runner.retry() }
            case .ready:
                content()
        }
    }
}

extension LifecycleContainer where Splash == LifecycleSplash {
    /// Convenience initializer using the built-in `LifecycleSplash`.
    public init(
        _ runner: LifecycleRunner,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(runner, splash: { LifecycleSplash() }, content: content)
    }
}

/// While a step runs, show its active presentation if it has one, otherwise
/// fall back to the splash. Observing `bridge.presentation` makes a deferred
/// (`presenting(after:)`) presentation appear without a phase change.
private struct LifecycleRunningView<Splash: View>: View {
    let bridge: LifecycleStepUIBridge
    let splash: () -> Splash

    var body: some View {
        if let presentation = bridge.presentation {
            presentation
        } else {
            splash()
        }
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
