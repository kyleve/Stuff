import SnapshotKit
import SwiftUI

/// Throw's controller-scene root. Every scene receives the same session instance.
public struct ThrowRootView: View {
    private let session: ThrowSession
    @State private var outputs = ControllerProjectionOutputs()
    @Environment(\.colorScheme) private var colorScheme

    public init(session: ThrowSession) {
        self.session = session
    }

    public var body: some View {
        Group {
            switch session.launchState {
                case .loading:
                    ThrowLaunchLoadingView()
                case .onboarding:
                    ThrowOnboardingView(session: session, outputs: outputs)
                case .ready:
                    ThrowDashboardView(session: session, outputs: outputs)
                case let .failed(failure):
                    ThrowLaunchFailureView(
                        failure: failure,
                        retry: session.startLaunch,
                    )
            }
        }
        .throwBroadwayRoot()
        .environment(\.throwDateProvider, session.dateProvider)
        .onChange(of: colorScheme, initial: true) { _, newValue in
            session.updateControllerColorScheme(newValue)
        }
    }
}

#if DEBUG
    extension ThrowRootView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Loading",
                configurations: .fullContentScreenDefaults,
                settle: .immediate,
            ) {
                ThrowRootView(session: .loadingRootSnapshotFixture())
            }
            SnapshotCase(
                name: "Onboarding",
                configurations: .fullContentScreenDefaults,
                settle: .immediate,
            ) {
                ThrowRootView(session: .onboardingFixture())
            }
            SnapshotCase(
                name: "Dashboard",
                configurations: .fullContentScreenDefaults,
                settle: .immediate,
            ) {
                ThrowRootView(session: .rootDashboardSnapshotFixture())
            }
            SnapshotCase(
                name: "Launch Failure",
                configurations: .fullContentScreenDefaults,
                settle: .immediate,
            ) {
                ThrowRootView(session: .failedRootSnapshotFixture())
            }
        }
    }

    #Preview("Loading") {
        ThrowRootView(session: .loadingRootSnapshotFixture())
    }

    #Preview("Onboarding") {
        ThrowRootView(session: .onboardingFixture())
    }

    #Preview("Dashboard") {
        ThrowRootView(session: .rootDashboardSnapshotFixture())
    }

    #Preview("Launch Failure") {
        ThrowRootView(session: .failedRootSnapshotFixture())
    }
#endif
