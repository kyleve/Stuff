import SwiftUI

/// The root view that renders a `Launcher`'s `phase`.
///
/// The launch sequence is only the *prerequisites*; the destination — the
/// app's real, "logged-in" UI — is the `content` closure, shown when the
/// launcher reaches `.ready`. Pass an already-built launcher (created early,
/// e.g. in the app delegate, so a headless background launch works without a
/// window).
///
/// For a background launch, the container renders nothing at all (iOS never
/// shows UI for a headless relaunch and reclaims memory aggressively), so
/// `content` is never constructed even once the launcher reaches `.ready`.
public struct LaunchContainer<Content: View, Splash: View>: View {
    private let launcher: Launcher
    private let splash: () -> Splash
    private let content: () -> Content

    public init(
        _ launcher: Launcher,
        @ViewBuilder splash: @escaping () -> Splash,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.launcher = launcher
        self.splash = splash
        self.content = content
    }

    public var body: some View {
        if launcher.reason.isBackground {
            EmptyView()
        } else {
            phaseContent
        }
    }

    @ViewBuilder private var phaseContent: some View {
        switch launcher.phase {
            case .launching:
                splash()
            case let .running(_, handle):
                LaunchRunningView(handle: handle, splash: splash)
            case let .failed(failure):
                LaunchFailureView(failure: failure) { launcher.retry() }
            case .ready:
                content()
        }
    }
}

extension LaunchContainer where Splash == LaunchSplash {
    /// Convenience initializer using the built-in `LaunchSplash`.
    public init(
        _ launcher: Launcher,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.init(launcher, splash: { LaunchSplash() }, content: content)
    }
}

/// While a step runs, show its active presentation if it has one, otherwise
/// fall back to the splash. Observing `handle.presentation` makes a deferred
/// (`presenting(after:)`) presentation appear without a phase change.
private struct LaunchRunningView<Splash: View>: View {
    let handle: StepHandle
    let splash: () -> Splash

    var body: some View {
        if let presentation = handle.presentation {
            presentation
        } else {
            splash()
        }
    }
}

#if DEBUG
    #Preview("Launching") {
        LaunchContainer(
            Launcher(reason: .userForeground, sequence: LaunchSequence {
                Work("open") { _ in }
            }),
        ) {
            Text("App content")
        }
    }
#endif
