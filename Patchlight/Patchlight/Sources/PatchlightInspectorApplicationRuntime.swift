#if DEBUG
    import Inspector
    import PatchlightUI
    import SwiftUI
    import UIKit

    /// The standalone Inspector process; it does not create a Patchlight scope.
    @MainActor
    final class PatchlightInspectorApplicationRuntime: PatchlightApplicationRuntime {
        private let modeController: InspectorModeController

        init(modeController: InspectorModeController) {
            self.modeController = modeController
        }

        func didFinishLaunching(
            application _: UIApplication,
            options _: [UIApplication.LaunchOptionsKey: Any]?,
        ) -> Bool {
            true
        }

        func makeRootView() -> AnyView {
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                preconditionFailure("Patchlight has no bundle identifier")
            }
            return AnyView(PatchlightDeveloperRootView(
                modeController: modeController,
                bundleIdentifier: bundleIdentifier,
            ))
        }
    }
#endif
