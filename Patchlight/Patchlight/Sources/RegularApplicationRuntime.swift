import LifecycleKit
import PatchlightUI
import SwiftUI
import UIKit

/// The shipping Patchlight process and its one lifecycle runner.
@MainActor
final class RegularApplicationRuntime: PatchlightApplicationRuntime {
    private let launcher = PatchlightLaunch.makeLauncher(reason: .undetermined)

    func didFinishLaunching(
        application _: UIApplication,
        options _: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool {
        Task { [launcher] in await launcher.run() }
        return true
    }

    func makeRootView() -> AnyView {
        AnyView(PatchlightRootView(launcher: launcher))
    }
}
