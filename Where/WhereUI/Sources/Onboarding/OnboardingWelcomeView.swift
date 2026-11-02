import SnapshotKit
import SwiftUI

/// The shared completion screen for first-run setup, Demo, and the developer preview.
struct OnboardingWelcomeView: View {
    var body: some View {
        LaunchSplashView(caption: .welcome)
    }
}

#if DEBUG
    extension OnboardingWelcomeView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereThemeSnapshot(name: "Welcome", configurations: .screenRepresentative) {
                OnboardingWelcomeView()
            }
        }
    }

    extension OnboardingWelcomeView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            OnboardingWelcomeView.self,
            title: "Welcome to Where",
            navigationContainer: .none,
        )
    }

    #Preview { OnboardingWelcomeView.snapshotPreviews }
#endif
