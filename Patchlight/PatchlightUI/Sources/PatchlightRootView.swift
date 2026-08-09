import LifecycleKit
import LifecycleKitUI
import SwiftUI

/// Patchlight's lifecycle-gated root and the only shipping UI entry point.
public struct PatchlightRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let launcher: LifecycleRunner<PatchlightApplicationSession>
    private let drivesLauncher: Bool

    public init(
        launcher: LifecycleRunner<PatchlightApplicationSession>,
        drivesLauncher: Bool = false,
    ) {
        self.launcher = launcher
        self.drivesLauncher = drivesLauncher
    }

    /// Preview/test convenience; the app runtime constructs and starts its own runner.
    @MainActor
    public init() {
        launcher = PatchlightLaunch.makeLauncher(reason: .userForeground)
        drivesLauncher = true
    }

    public var body: some View {
        LifecycleContainer(
            launcher,
            transition: .opacity,
            animation: .easeInOut(duration: 0.2),
            splash: { _ in PatchlightLaunchSplashView() },
            failure: { PatchlightLaunchFailureView(failure: $0) },
        ) { _ in
            PatchlightDashboardView()
        }
        .patchlightBroadwayRoot()
        .task {
            guard drivesLauncher else { return }
            await launcher.run()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await launcher.enterForeground() }
        }
    }
}

#Preview {
    PatchlightRootView()
}
