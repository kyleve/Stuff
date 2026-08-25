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
            if session.setupCompleted {
                ThrowDashboardView(session: session, outputs: outputs)
            } else {
                ThrowOnboardingView(session: session, outputs: outputs)
            }
        }
        .throwBroadwayRoot()
        .environment(\.throwDateProvider, session.dateProvider)
        .task {
            session.updateControllerColorScheme(colorScheme)
            await session.start()
        }
        .onChange(of: colorScheme) { _, newValue in
            session.updateControllerColorScheme(newValue)
        }
    }
}

#if DEBUG
    extension ThrowRootView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
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
        }
    }

    #Preview("Onboarding") {
        ThrowRootView(session: .onboardingFixture())
    }

    #Preview("Dashboard") {
        ThrowRootView(session: .rootDashboardSnapshotFixture())
    }
#endif
